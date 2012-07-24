//
// Copyright (c) 2012 Azavea
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
//  sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//  

#import <UIKit/UIKit.h>
#import "OTMScrollAwareViewController.h"
#import "OTMDetailTableViewCell.h"
#import "OTMPictureTaker.h"
#import "OTMMapDetailCellRenderer.h"

@class OTMTreeDetailViewController; // declared early so the delegate can use the type in its declaration

@protocol OTMTreeDetailViewDelegate <NSObject>
@required
- (void)viewController:(OTMTreeDetailViewController *)viewController addedTree:(NSDictionary *)details;

- (void)viewController:(OTMTreeDetailViewController *)viewController editedTree:(NSDictionary *)details withOriginalLocation:(CLLocationCoordinate2D)coordinate;

- (void)treeAddCanceledByViewController:(OTMTreeDetailViewController *)viewController;

- (void)plotDeletedByViewController:(OTMTreeDetailViewController *)viewController;
@end

@interface OTMTreeDetailViewController : OTMScrollAwareViewController<UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIActionSheetDelegate> {
    BOOL editMode;
    BOOL updated;
    NSMutableDictionary *data;
    
    NSArray *txToEditRemove;
    NSArray *txToEditReload;
    
    NSArray *editFields;
    NSMutableArray *allFields;
    
    NSArray *curFields;

    NSString *deleteType;
}

@property (nonatomic,weak) id<OTMTreeDetailViewDelegate> delegate;

@property (nonatomic,strong) IBOutlet OTMPictureTaker *pictureTaker;

@property (nonatomic,strong) IBOutlet UITableView *tableView;
@property (nonatomic,strong) IBOutlet UILabel* address;
@property (nonatomic,strong) IBOutlet UILabel* species;
@property (nonatomic,strong) IBOutlet UILabel* lastUpdateDate;
@property (nonatomic,strong) IBOutlet UILabel* updateUser;
@property (nonatomic,strong) IBOutlet UIImageView* imageView;
@property (nonatomic,strong) IBOutlet UIView* headerView;
@property (nonatomic) CLLocationCoordinate2D originalLocation;

@property (nonatomic,strong) IBOutlet UITableViewCell *acell;

/**
 * Dictionary[String,String] of tree detail key-value pairs
 */
@property (nonatomic, strong) NSDictionary* data;

/**
 * Array[Array[OTMDetailCellRenderer]] keys to display in the main table
 *
 * Each element in the outer array represents a section
 * and each element in the inner array represents a row.
 * 
 * The first row is the title of the section (which can
 * be the empty string)
 */
@property (nonatomic, strong) NSArray* keys;

- (IBAction)startOrCommitEditing:(id)sender;
- (IBAction)cancelEditing:(id)sender;

@end
