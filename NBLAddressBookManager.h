//
//  NBLAddressBookManager.h
//  Contact Notes
//
//  Created by David Keegan on 11/24/12.
//  Copyright (c) 2012 David Keegan. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const NBLAddressBookManagerAddressBookUpdated;

@class NBLContact;
@class PJTernarySearchTree;

@interface NBLAddressBookManager : NSObject

@property (strong, readonly) PJTernarySearchTree *tagSearchTree;
@property (nonatomic, readonly) ABAddressBookRef addressBook;
@property (readonly) BOOL sortByFirstName;
@property (readonly) BOOL hasAccess;

+ (id)sharedManager;

- (BOOL)saveWithError:(NSError **)error;
- (NBLContact *)contactWithName:(NSString *)name orRecordID:(NSNumber *)RecordID;
- (void)requestContactsWithBlock:(void(^)(BOOL granted, NSArray *contacts, NSError *error))block;
- (BOOL)removeContact:(NBLContact *)contact error:(NSError **)error;

+ (void)findTagsInText:(NSString *)text withBlock:(void(^)(NSString *matchString, NSRange matchRange))block;

@end
