//
//  OTMProfileViewController.m
//  OpenTreeMap
//
//  Created by Adam Hinz on 3/26/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "OTMProfileViewController.h"

#define kOTMProfileViewControllerSectionInfo 0
#define kOTMProfileViewControllerSectionChangePassword 1
#define kOTMProfileViewControllerSectionChangeProfilePicture 2
#define kOTMProfileViewControllerSectionRecentEdits 3

#define kOTMProfileViewControllerSectionInfoCellIdentifier @"kOTMProfileViewControllerSectionInfoCellIdentifier"
#define kOTMProfileViewControllerSectionChangePasswordCellIdentifier @"kOTMProfileViewControllerSectionChangePasswordCellIdentifier"
#define kOTMProfileViewControllerSectionChangeProfilePictureCellIdentifier @"kOTMProfileViewControllerSectionChangeProfilePictureCellIdentifier"
#define kOTMProfileViewControllerSectionRecentEditsCellIdentifier @"kOTMProfileViewControllerSectionRecentEditsCellIdentifier"

@interface OTMProfileViewController ()

@end

@implementation OTMProfileViewController

@synthesize tableView, user, pictureTaker, recentActivity, loadingView;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (UITableViewCell *)tableView:(UITableView *)tblView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([indexPath section] == kOTMProfileViewControllerSectionInfo) {
        return [self tableView:tblView infoCellForRow:[indexPath row]];
    } else if ([indexPath section] == kOTMProfileViewControllerSectionChangePassword) {
        UITableViewCell *cell = [tblView dequeueReusableCellWithIdentifier:kOTMProfileViewControllerSectionChangePasswordCellIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:kOTMProfileViewControllerSectionChangePasswordCellIdentifier];
        }
        
        cell.textLabel.text = @"Change Password";
        
        return cell;
    } else if ([indexPath section] == kOTMProfileViewControllerSectionChangeProfilePicture) {
        UITableViewCell *cell = [tblView dequeueReusableCellWithIdentifier:kOTMProfileViewControllerSectionChangeProfilePictureCellIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:kOTMProfileViewControllerSectionChangeProfilePictureCellIdentifier];
        }
        cell.textLabel.text = @"Change Profile Picture";    
        
        return cell;
    } else {
        UITableViewCell *cell = [tblView dequeueReusableCellWithIdentifier:kOTMProfileViewControllerSectionRecentEditsCellIdentifier];
        
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                          reuseIdentifier:kOTMProfileViewControllerSectionRecentEditsCellIdentifier];
        }
        
        cell.textLabel.text = [[self.recentActivity objectAtIndex:[indexPath row]] objectForKey:@"name"];
        
        return cell;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tblView infoCellForRow:(NSInteger)row {
   
    NSString *itemTitle = nil;
    NSString *itemValue = nil;
    
    switch (row) {
        case 0:
            itemTitle = @"Username";
            itemValue = self.user.username;
            break;

        case 1:
            itemTitle = @"First Name";
            itemValue = self.user.firstName;
            break;

        case 2:
            itemTitle = @"Last Name";
            itemValue = self.user.lastName;
            break;

        case 3:
            itemTitle = @"Zip Code";
            itemValue = self.user.zipcode;
            break;

        default:
            break;
    }
    
    UITableViewCell *cell = [tblView dequeueReusableCellWithIdentifier:kOTMProfileViewControllerSectionInfoCellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:kOTMProfileViewControllerSectionInfoCellIdentifier];
    }    
    
    cell.textLabel.text = itemTitle;
    cell.detailTextLabel.text = itemValue;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    return cell;
}
        
- (void)tableView:(UITableView *)tblView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if ([path section] == kOTMProfileViewControllerSectionChangePassword) {
        [self performSegueWithIdentifier:@"ChangePassword" sender:self];
    } else if ([path section] == kOTMProfileViewControllerSectionChangeProfilePicture) {
        [pictureTaker getPictureInViewController:self
                                        callback:^(UIImage *image) 
         {
             if (image) {
                 self.user.photo = image;
                 
                 [[[OTMEnvironment sharedEnvironment] api] setProfilePhoto:user
                                                                  callback:^(id json, NSError *error) 
                  {
                      if (error != nil) {
                          [[[UIAlertView alloc] initWithTitle:@"Error"
                                                      message:@"Could not save photo"
                                                     delegate:nil
                                            cancelButtonTitle:@"OK"
                                            otherButtonTitles:nil] show];
                          }
                  }];
             }
         }];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case kOTMProfileViewControllerSectionInfo:
            return 4;
        case kOTMProfileViewControllerSectionChangePassword:
        case kOTMProfileViewControllerSectionChangeProfilePicture:
            return 1;
        case kOTMProfileViewControllerSectionRecentEdits:
            return [self.recentActivity count];
    }
    
    return 0;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 4;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    [self.loadingView removeFromSuperview];
    [self.tableView addSubview:self.loadingView];
    
    self.loadingView.hidden = YES;

    if (pictureTaker == nil) {
        pictureTaker = [[OTMPictureTaker alloc] init];
    }
    if (self.recentActivity == nil) {
        self.recentActivity = [NSMutableArray array];
    }
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (void)viewWillAppear:(BOOL)animated {
    OTMLoginManager* mgr = [(OTMAppDelegate*)[[UIApplication sharedApplication] delegate] loginManager];

    [mgr presentModelLoginInViewController:self.parentViewController callback:^(BOOL success, OTMUser *aUser) {
        if (success) {
            self.user = aUser;
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kOTMProfileViewControllerSectionInfo]
                          withRowAnimation:UITableViewRowAnimationNone];
            
            if ([self.recentActivity count] == 0) {
                [self loadRecentEdits];
            }
        }
    }];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    if (self.loadingView.hidden == YES && scrollView.contentOffset.y > scrollView.contentSize.height - 400) {
        heightOffset = self.loadingView.frame.size.height + 5;
        
        self.tableView.contentSize = CGSizeMake(self.tableView.contentSize.width,
                                                self.tableView.contentSize.height +
                                                heightOffset);
        
        self.loadingView.frame = CGRectMake(0,
                                            self.tableView.contentSize.height - heightOffset,
                                            320,
                                            40);
        self.loadingView.hidden = NO;
        [self loadRecentEdits];
    }

}

-(void)loadRecentEdits {
    if (loading == YES) {
        return;
    }
    
    loading = YES;
    [[[OTMEnvironment sharedEnvironment] api] getRecentActionsForUser:self.user
                                                               offset:[self.recentActivity count]
                                                             callback:
     ^(NSArray *json, NSError *error) {
         for(NSDictionary *event in json) {
             if ([self.recentActivity indexOfObjectPassingTest:^(NSDictionary *obj, NSUInteger idx, BOOL *stop) {
                 if ([[obj valueForKey:@"id"] intValue] == [[event valueForKey:@"id"] intValue]) {
                     *stop = YES;
                     return YES;
                 } else {
                     return NO;
                 }
             }] == NSNotFound) {
                 [self.recentActivity addObject:event];
             }
                     
         }
         
         [UIView animateWithDuration:0.3
                          animations:
         ^{
             self.tableView.contentSize = CGSizeMake(self.tableView.contentSize.width,
                                                     self.tableView.contentSize.height - heightOffset);
         }
                          completion:^(BOOL finished) 
         {
             [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:kOTMProfileViewControllerSectionRecentEdits]
                           withRowAnimation:UITableViewRowAnimationNone];             
             
             self.loadingView.hidden = YES;
         }];
         
         loading = NO;
     }];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

@end
