//
//  KGNContact.h
//  KGNAddressBook
//
//  Created by David Keegan on 11/23/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

@import AddressBook;

extern NSString *const KGNAddressBookContactNoteChangedNotification;
extern NSString *const KGNAddressBookContactIsInvalidNotification;

@interface KGNAddressBookContact : NSObject

@property (readonly) UIImage *profileImage;
@property (nonatomic, readonly) ABRecordRef record;
@property (nonatomic, readonly) BOOL isOrganization;
@property (strong, nonatomic, readonly) NSString *note;
@property (strong, nonatomic, readonly) NSString *firstName;
@property (strong, nonatomic, readonly) NSString *lastName;
@property (strong, nonatomic, readonly) NSString *organizationName;
@property (strong, nonatomic, readonly) NSString *nickname;
@property (strong, nonatomic, readonly) NSString *displayName;
@property (strong, nonatomic, readonly) NSString *sectionName;
@property (readonly, getter=isValid) BOOL valid;

+ (instancetype)contactWithAddressBookRecord:(ABRecordRef)record;
+ (NSCache *)profileImageCache;

- (void)mergeInfoFromRecord:(ABRecordRef)record;
- (void)updateContact;
- (void)updateNote;

- (BOOL)addURL:(NSURL *)url withName:(NSString *)name andError:(NSError **)error;
- (BOOL)setNote:(NSString *)note error:(NSError **)error;

@end
