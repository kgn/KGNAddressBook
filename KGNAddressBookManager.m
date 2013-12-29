//
//  NBLAddressBookManager.m
//  Contact Notes
//
//  Created by David Keegan on 11/24/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

#import "KGNAddressBookManager.h"
#import "KGNAddressBookContact.h"

NSString *const KGNAddressBookManagerAddressBookUpdateNotification = @"KGNAddressBookManagerAddressBookUpdateNotification";

@implementation KGNAddressBookManager

+ (id)sharedManager{
    static id sharedManager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[[self class] alloc] init];
        [sharedManager updateAddressBook];

        [[NSNotificationCenter defaultCenter]
         addObserver:sharedManager selector:@selector(updateAddressBook)
         name:UIApplicationDidBecomeActiveNotification object:nil];
    });
    return sharedManager;
}

// TODO: add error?
- (void)updateAddressBook{
    if([self hasAccess]){
        if(_addressBook == NULL){
            CFErrorRef error = NULL;
            _addressBook = ABAddressBookCreateWithOptions(NULL, &error);
            if(error){
                NSLog(@"%@:%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
            }
        }else{
            ABAddressBookRevert(_addressBook);
        }
    }else{
        _addressBook = NULL;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:KGNAddressBookManagerAddressBookUpdateNotification object:self];
}

- (BOOL)hasAccess{
    ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
    return (status == kABAuthorizationStatusAuthorized);
}

- (BOOL)sortByFirstName{
    return (ABPersonGetSortOrdering() == kABPersonSortByFirstName);
}

- (void)requestContactsWithBlock:(void(^)(BOOL granted, NSArray *contacts, NSError *error))block{
    __typeof__(self) __weak wself = self;
    ABAddressBookRequestAccessWithCompletion([self addressBook], ^(bool granted, CFErrorRef error){
        dispatch_async(dispatch_get_main_queue(), ^{
            if(!granted){
                NSLog(@"%@:%@ NOT GRANTED", NSStringFromClass([self class]), NSStringFromSelector(_cmd));
                block(granted, nil, CFBridgingRelease(error));
                return;
            }
            if(error){
                NSLog(@"%@:%@ %@", NSStringFromClass([self class]), NSStringFromSelector(_cmd), error);
                block(granted, nil, CFBridgingRelease(error));
                return;
            }

            CFArrayRef allContacts = ABAddressBookCopyArrayOfAllPeople([wself addressBook]);
            if(allContacts == nil){
                block(granted, nil, nil);
                return;
            }
            CFMutableArrayRef allMutableSortedContacts = CFArrayCreateMutableCopy(kCFAllocatorDefault, CFArrayGetCount(allContacts), allContacts);
            CFArraySortValues(allMutableSortedContacts, CFRangeMake(0, CFArrayGetCount(allMutableSortedContacts)), (CFComparatorFunction)ABPersonComparePeopleByName, (void *)ABPersonGetSortOrdering());
            CFRelease(allContacts);

            NSMutableArray *contacts = [NSMutableArray array];
            NSMutableIndexSet *linkedRecords = [NSMutableIndexSet indexSet];
            NSArray *allSortedContacts = CFBridgingRelease(allMutableSortedContacts);
            for(id recordObj in allSortedContacts){
                ABRecordRef record = (__bridge ABRecordRef)recordObj;
                ABRecordID recordID = ABRecordGetRecordID(record);
                if([linkedRecords containsIndex:(NSUInteger)recordID]){
                    continue;
                }

                CFErrorRef innerError = NULL;
                NSString *note = CFBridgingRelease(ABRecordCopyValue(record, kABPersonNoteProperty));
                ABRecordSetValue(record, kABPersonNoteProperty, (__bridge CFStringRef)note, &innerError);
                if(innerError){
                    continue;
                }

                KGNAddressBookContact *contact = [KGNAddressBookContact contactWithAddressBookRecord:record];
                NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(record));
                for(id linkedRecordObj in linkedContacts){
                    ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
                    ABRecordID linkedRecordID = ABRecordGetRecordID(linkedRecord);
                    [linkedRecords addIndex:(NSUInteger)linkedRecordID];
                    [contact mergeInfoFromRecord:linkedRecord];
                }
                [contacts addObject:contact];
            }

            // Just in case revert any changes
            if(ABAddressBookHasUnsavedChanges([self addressBook])){
                ABAddressBookRevert([self addressBook]);
            }

            block(granted, [NSArray arrayWithArray:contacts], CFBridgingRelease(error));
        });
    });
}

- (BOOL)removeContact:(KGNAddressBookContact *)contact error:(NSError **)error{
    CFErrorRef cferror = NULL;
    BOOL success = ABAddressBookRemoveRecord([self addressBook], contact.record, &cferror);
    if(!success){
        if(cferror && error != nil){
            *error = CFBridgingRelease(cferror);
        }
        return NO;
    }
    return [self saveWithError:error];

}

- (KGNAddressBookContact *)contactWithName:(NSString *)name orRecordID:(NSNumber *)recordID{
    KGNAddressBookContact *contact;
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *contacts = CFBridgingRelease(ABAddressBookCopyPeopleWithName([self addressBook], (__bridge CFStringRef)name));
    if([contacts count] == 1){
        ABRecordRef record = (__bridge ABRecordRef)contacts[0];
        contact = [KGNAddressBookContact contactWithAddressBookRecord:record];
    }else if([contacts count] > 1){
        if(recordID){
            for(id recordObj in contacts){
                ABRecordRef record = (__bridge ABRecordRef)recordObj;
                if([recordID integerValue] == ABRecordGetRecordID(record)){
                    contact = [KGNAddressBookContact contactWithAddressBookRecord:record];
                    break;
                }
            }
        }

        if(!contact){
            ABRecordRef record = (__bridge ABRecordRef)contacts[0];
            contact = [KGNAddressBookContact contactWithAddressBookRecord:record];
        }
    }

    if(contact){
        NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(contact.record));
        for(id linkedRecordObj in linkedContacts){
            ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
            [contact mergeInfoFromRecord:linkedRecord];
        }
        return contact;
    }

    return nil;
}

- (BOOL)saveWithError:(NSError **)error{
    bool shouldSave = ABAddressBookHasUnsavedChanges([self addressBook]);
    if(!shouldSave){
        return NO;
    }

    CFErrorRef cferror = NULL;
    bool success = ABAddressBookSave([self addressBook], &cferror);
    if(!success){
        if(cferror && error != nil){
            *error = CFBridgingRelease(cferror);
        }
        return NO;
    }

    return YES;
}

@end
