//
//  NBLAddressBookManager.m
//  Contact Notes
//
//  Created by David Keegan on 11/24/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

#import "NBLAddressBookManager.h"
#import "BBlock.h"
#import "NBLContact.h"
#import "PJTernarySearchTree.h"

NSString *const NBLAddressBookManagerAddressBookUpdated = @"NBLAddressBookManagerAddressBookUpdated";

@interface NBLAddressBookManager()
@property (strong, readwrite) PJTernarySearchTree *tagSearchTree;
@end

@implementation NBLAddressBookManager

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
    [[NSNotificationCenter defaultCenter] postNotificationName:NBLAddressBookManagerAddressBookUpdated object:self];
}

- (BOOL)hasAccess{
    ABAuthorizationStatus status = ABAddressBookGetAuthorizationStatus();
    return (status == kABAuthorizationStatusAuthorized);
}

- (BOOL)sortByFirstName{
    return (ABPersonGetSortOrdering() == kABPersonSortByFirstName);
}

- (void)requestContactsWithBlock:(void(^)(BOOL granted, NSArray *contacts, NSError *error))block{
    BBlockWeakSelf wself = self;
    CFTimeInterval before = CFAbsoluteTimeGetCurrent();
    PJTernarySearchTree *tagSearchTree = [[PJTernarySearchTree alloc] init];
//    NSLog(@"%@", [tagSearchTree retrievePrefix:@""]);
    ABAddressBookRequestAccessWithCompletion([self addressBook], ^(bool granted, CFErrorRef error){
        [BBlock dispatchOnMainThread:^{
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
            CFArraySortValues(allMutableSortedContacts, CFRangeMake(0, CFArrayGetCount(allMutableSortedContacts)), (CFComparatorFunction)ABPersonComparePeopleByName, (void*)ABPersonGetSortOrdering());
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

                if(note){
                    BBlockWeakObject(tagSearchTree) wtagSearchTree = tagSearchTree;
                    [BBlock dispatchOnHighPriorityConcurrentQueue:^{
                        [[wself class] findTagsInText:note withBlock:^(NSString *matchString, NSRange matchRange){
                            [wtagSearchTree insertString:[[matchString substringFromIndex:1] lowercaseString]];
                        }];
                    }];
                }

                NBLContact *contact = [NBLContact contactWithAddressBookRecord:record];
                NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(record));
                for(id linkedRecordObj in linkedContacts){
                    ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
                    ABRecordID linkedRecordID = ABRecordGetRecordID(linkedRecord);
                    [linkedRecords addIndex:(NSUInteger)linkedRecordID];
                    [contact mergeInfoFromRecord:linkedRecord];
                }
                [contacts addObject:contact];
            }

            self.tagSearchTree = tagSearchTree;

            // Just in case revert any changes
            if(ABAddressBookHasUnsavedChanges([self addressBook])){
                ABAddressBookRevert([self addressBook]);
            }

            CFTimeInterval after = CFAbsoluteTimeGetCurrent();
            [Flurry logEvent:@"ContactsTime" withParameters:@{@"time":@((after-before)*1000)}];
            NSLog(@"Contacts time %zdms", (NSUInteger)((after - before) * 1000));

            block(granted, [NSArray arrayWithArray:contacts], CFBridgingRelease(error));
        }];
    });
}

- (BOOL)removeContact:(NBLContact *)contact error:(NSError **)error{
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

- (NBLContact *)contactWithName:(NSString *)name orRecordID:(NSNumber *)recordID{
    NBLContact *contact;
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSArray *contacts = CFBridgingRelease(ABAddressBookCopyPeopleWithName([self addressBook], (__bridge CFStringRef)name));
    if([contacts count] == 1){
        ABRecordRef record = (__bridge ABRecordRef)contacts[0];
        contact = [NBLContact contactWithAddressBookRecord:record];
    }else if([contacts count] > 1){
        if(recordID){
            for(id recordObj in contacts){
                ABRecordRef record = (__bridge ABRecordRef)recordObj;
                if([recordID integerValue] == ABRecordGetRecordID(record)){
                    contact = [NBLContact contactWithAddressBookRecord:record];
                    break;
                }
            }
        }

        if(!contact){
            ABRecordRef record = (__bridge ABRecordRef)contacts[0];
            contact = [NBLContact contactWithAddressBookRecord:record];
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

+ (void)findTagsInText:(NSString *)text withBlock:(void(^)(NSString *matchString, NSRange matchRange))block{
    if(text == nil){
        return;
    }

    // Add a space to the front to match tags at the very beginning of the string
    text = [NSString stringWithFormat:@" %@", text];

    NSError *error = nil;
    NSString *pattern = [NSString stringWithFormat:@"\\s+%@*(%@{1}[\\w\\d\\_]+)", NBLPreferencesNoteTagCharacter, NBLPreferencesNoteTagCharacter];
    NSRegularExpression *regex =
    [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if(error){
        [Flurry logError:NBLClassAndSelector message:@"Error while trying to regex contact note" error:error];
    }
    NSArray *matches = [regex matchesInString:text options:0 range:NSMakeRange(0, text.length)];
    for(NSTextCheckingResult *match in matches){
        NSRange matchRange = [match rangeAtIndex:1];
        NSString *matchString = [text substringWithRange:matchRange];
        matchRange.location -= 1; // step backwards because of the space we added
        block(matchString, matchRange);
    }
}

@end
