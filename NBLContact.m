//
//  NBLPerson.m
//  Contact Notes
//
//  Created by David Keegan on 11/23/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

#import "NBLContact.h"
#import "NBLAddressBookManager.h"
#import "NSObject+BBlock.h"
#import "TTTAddressFormatter.h"

NSString *const NBLContactNoteChangedNotification = @"NBLContactNoteChangedNotification";
NSString *const NBLContactIsInvalidNotification = @"NBLContactIsInvalidNotification";

@interface NBLContact()
@property (nonatomic, readwrite) ABRecordRef record;
@property (nonatomic, readwrite) BOOL isOrganization;
@property (strong, nonatomic, readwrite) NSString *firstName;
@property (strong, nonatomic, readwrite) NSString *lastName;
@property (strong, nonatomic, readwrite) NSString *organizationName;
@property (strong, nonatomic, readwrite) NSString *nickname;
@property (strong, nonatomic, readwrite) NSString *displayName;
@property (strong, nonatomic, readwrite) NSString *sectionName;
@end

@implementation NBLContact

+ (id)contactWithAddressBookRecord:(ABRecordRef)record{
    return [[self alloc] initWithAddressBookRecord:record];
}

- (id)initWithAddressBookRecord:(ABRecordRef)record{
    if(!(self = [super init])){
        return nil;
    }

    self.record = record;
    [self mergeInfoFromRecord:record];

    return self;
}

- (void)mergeInfoFromRecord:(ABRecordRef)record{
    NSString *note = CFBridgingRelease(ABRecordCopyValue(record, kABPersonNoteProperty));
    if([self.note length] == 0 && [note length] > 0){
        [self changeValueWithKey:@"note" changeBlock:^{
            _note = note;
        }];
    }

    self.displayName = CFBridgingRelease(ABRecordCopyCompositeName(record));
    self.nickname = CFBridgingRelease(ABRecordCopyValue(record, kABPersonNicknameProperty));
    self.firstName = CFBridgingRelease(ABRecordCopyValue(record, kABPersonFirstNameProperty));
    self.lastName = CFBridgingRelease(ABRecordCopyValue(record, kABPersonLastNameProperty));
    self.organizationName = CFBridgingRelease(ABRecordCopyValue(record, kABPersonOrganizationProperty));

    if([self.displayName isEqualToString:self.organizationName]){
        self.isOrganization = YES;
    }

    if([[NBLAddressBookManager sharedManager] sortByFirstName]){
        self.sectionName = self.firstName ?: self.displayName;
    }else{
        self.sectionName = self.lastName ?: self.displayName;
    }
}

- (BOOL)addURL:(NSURL *)url withName:(NSString *)name andError:(NSError **)error{
    if(!url || !name){
        return NO;
    }

    CFErrorRef cferror = NULL;
    ABMutableMultiValueRef urlMultiValue = ABMultiValueCreateMutable(kABStringPropertyType);
    ABMultiValueAddValueAndLabel(urlMultiValue, (__bridge CFTypeRef)[url absoluteString], (__bridge CFStringRef)(name), NULL);
    bool success = ABRecordSetValue(self.record, kABPersonURLProperty, urlMultiValue, &cferror);
    CFRelease(urlMultiValue);
    if(!success){
        if(cferror && error != nil){
            *error = CFBridgingRelease(cferror);
        }
        return NO;
    }
    return YES;
}

+ (NSCache *)profileImageCache{
    static dispatch_once_t onceToken;
    static NSCache *profileImageCache;
    dispatch_once(&onceToken, ^{
        profileImageCache = [[NSCache alloc] init];
    });
    return profileImageCache;
}

- (UIImage *)profileImage{
    if(!self.record){
        return nil;
    }

    NSNumber *identifer = @(ABRecordGetRecordID(self.record));
    id cachedObject = [[[self class] profileImageCache] objectForKey:identifer];
    if([cachedObject isKindOfClass:[UIImage class]]){
        return cachedObject;
    }
    if([cachedObject isKindOfClass:[NSNull class]]){
        return nil;
    }

    UIImage *image = nil;
    if(ABPersonHasImageData(self.record)){
        image = [UIImage imageWithData:CFBridgingRelease(ABPersonCopyImageDataWithFormat(self.record, kABPersonImageFormatThumbnail))];
    }else{
        NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(self.record));
        for(id linkedRecordObj in linkedContacts){
            ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
            if(ABPersonHasImageData(linkedRecord)){
                image = [UIImage imageWithData:CFBridgingRelease(ABPersonCopyImageDataWithFormat(linkedRecord, kABPersonImageFormatThumbnail))];
                break;
            }
        }
    }

    [[[self class] profileImageCache] setObject:image ?: [NSNull null] forKey:identifer];

    return image;
}

- (void)setSectionName:(NSString *)sectionName{
    NSCharacterSet *charactersToRemove =
    [[NSCharacterSet alphanumericCharacterSet] invertedSet];
    sectionName = [sectionName stringByTrimmingCharactersInSet:charactersToRemove];
    NSArray *components = [sectionName componentsSeparatedByCharactersInSet:charactersToRemove];
    components = [components filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"self <> ''"]];
    sectionName = [components componentsJoinedByString:@""];
    if(![_sectionName isEqualToString:sectionName]){
        _sectionName = sectionName ?: @"";
    }
}

- (BOOL)isValid{
    ABRecordID recordID = ABRecordGetRecordID(self.record);
    ABRecordRef record = ABAddressBookGetPersonWithRecordID([[NBLAddressBookManager sharedManager] addressBook], recordID);
    return (record != NULL);
}

- (void)updateContact{
    ABRecordID recordID = ABRecordGetRecordID(self.record);
    ABRecordRef record = ABAddressBookGetPersonWithRecordID([[NBLAddressBookManager sharedManager] addressBook], recordID);
    if(record){
        [self mergeInfoFromRecord:record];
        [self updateNoteWithRecord:record];
    }
}

- (void)updateNote{
    ABRecordID recordID = ABRecordGetRecordID(self.record);
    ABRecordRef record = ABAddressBookGetPersonWithRecordID([[NBLAddressBookManager sharedManager] addressBook], recordID);
    [self updateNoteWithRecord:record];
}

- (void)updateNoteWithRecord:(ABRecordRef)record{
    if(record){
        [self changeValueWithKey:@"note" changeBlock:^{
            _note = CFBridgingRelease(ABRecordCopyValue(record, kABPersonNoteProperty));
        }];
    }else{
        [self changeValueWithKey:@"note" changeBlock:^{
            _note = nil;
        }];
    }
}

- (BOOL)setNote:(NSString *)note error:(NSError **)error{
    if([note length] == 0){
        note = nil;
    }
    if(note == self.note || [self.note isEqualToString:note]){
        return NO;
    }
    if(!self.isValid){
        return NO;
    }

    CFErrorRef cferror = NULL;
    bool success = ABRecordSetValue(self.record, kABPersonNoteProperty, (__bridge CFStringRef)note, &cferror);
    if(!success){
        if(cferror && error != nil){
            *error = CFBridgingRelease(cferror);
        }
        return NO;
    }
    if(![[NBLAddressBookManager sharedManager] saveWithError:error]){
        return NO;
    }

    [self changeValueWithKey:@"note" changeBlock:^{
        _note = note;
    }];

    [[NSNotificationCenter defaultCenter]
     postNotificationName:NBLContactNoteChangedNotification object:self];
    return YES;
}

- (NSSet *)addresses{
    ABMultiValueRef addressMultiValue = ABRecordCopyValue(self.record, kABPersonAddressProperty);
    NSMutableSet *addressProfiles = [NSMutableSet setWithArray:CFBridgingRelease(ABMultiValueCopyArrayOfAllValues(addressMultiValue))];
    NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(self.record));
    for(id linkedRecordObj in linkedContacts){
        ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
        ABMultiValueRef linkedAddressMultiValue = ABRecordCopyValue(linkedRecord, kABPersonAddressProperty);
        NSArray *linkedAddressProfiles = CFBridgingRelease(ABMultiValueCopyArrayOfAllValues(linkedAddressMultiValue));
        [addressProfiles addObjectsFromArray:linkedAddressProfiles];
        CFRelease(linkedAddressMultiValue);
    }
    CFRelease(addressMultiValue);

    NSMutableSet *addresses = [NSMutableSet set];
    for(NSDictionary *addressProfile in addressProfiles){
        static dispatch_once_t onceToken;
        static TTTAddressFormatter *addressFormatter;
        dispatch_once(&onceToken, ^{
            addressFormatter = [[TTTAddressFormatter alloc] init];
        });
        NSString *address =
        [addressFormatter stringFromAddressWithStreet:addressProfile[(NSString *)kABPersonAddressStreetKey]
                                             locality:addressProfile[(NSString *)kABPersonAddressCityKey]
                                               region:addressProfile[(NSString *)kABPersonAddressStateKey]
                                           postalCode:addressProfile[(NSString *)kABPersonAddressZIPKey]
                                              country:addressProfile[(NSString *)kABPersonAddressCountryKey]];
        [addresses addObject:address];
    }

    return [NSSet setWithSet:addresses];
}

- (NSSet *)twitterAccounts{
    ABMultiValueRef socialProfileMultiValue = ABRecordCopyValue(self.record, kABPersonSocialProfileProperty);
    NSMutableSet *socialProfiles = [NSMutableSet setWithArray:CFBridgingRelease(ABMultiValueCopyArrayOfAllValues(socialProfileMultiValue))];
    NSArray *linkedContacts = CFBridgingRelease(ABPersonCopyArrayOfAllLinkedPeople(self.record));
    for(id linkedRecordObj in linkedContacts){
        ABRecordRef linkedRecord = (__bridge ABRecordRef)linkedRecordObj;
        ABMultiValueRef linkedSocialProfileMultiValue = ABRecordCopyValue(linkedRecord, kABPersonSocialProfileProperty);
        NSArray *linkedSocialProfiles = CFBridgingRelease(ABMultiValueCopyArrayOfAllValues(linkedSocialProfileMultiValue));
        [socialProfiles addObjectsFromArray:linkedSocialProfiles];
        CFRelease(linkedSocialProfileMultiValue);
    }
    CFRelease(socialProfileMultiValue);

    NSMutableSet *accounts = [NSMutableSet set];
    for(NSDictionary *socialProfile in socialProfiles){
        if([socialProfile[@"service"] isEqualToString:(__bridge NSString *)kABPersonSocialProfileServiceTwitter]){
            [accounts addObject:socialProfile[@"username"]];
        }
    }
    return [NSSet setWithSet:accounts];
}

- (BOOL)isEqual:(id)object{
    if([object isKindOfClass:[self class]]){
        if(self.record == [object record]){
            return YES;
        }
    }
    return NO;
}

- (NSString *)description{
    return [NSString stringWithFormat:@"<%@ name='%@'>", NSStringFromClass([self class]), self.displayName];
}

@end
