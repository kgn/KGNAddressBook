//
//  NBLAddressBookManager.h
//  Contact Notes
//
//  Created by David Keegan on 11/24/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

@import AddressBook;

extern NSString *const KGNAddressBookManagerAddressBookUpdateNotification;

@class KGNAddressBookContact;

@interface KGNAddressBookManager : NSObject

@property (nonatomic, readonly) ABAddressBookRef addressBook;
@property (readonly) BOOL sortByFirstName;
@property (readonly) BOOL hasAccess;

+ (id)sharedManager;

- (BOOL)saveWithError:(NSError **)error;
- (KGNAddressBookContact *)contactWithName:(NSString *)name orRecordID:(NSNumber *)RecordID;
- (void)requestContactsWithBlock:(void(^)(BOOL granted, NSArray *contacts, NSError *error))block;
- (BOOL)removeContact:(KGNAddressBookContact *)contact error:(NSError **)error;

@end
