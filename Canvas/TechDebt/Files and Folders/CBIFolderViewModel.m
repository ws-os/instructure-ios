//
// Copyright (C) 2016-present Instructure, Inc.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, version 3 of the License.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//
    
    

#import "CBIFolderViewModel.h"
#import "CBIFileViewModel.h"
@import CanvasKit;
#import "Router.h"
#import "EXTScope.h"

#import "ReceivedFilesViewController.h"
#import "UIImage+TechDebt.h"

@import CanvasCore;
@import CanvasKeymaster;

@interface CBIDeleteFolderConfirmationAlertView : UIAlertView
@property (nonatomic) MLVCTableViewController *tableViewController;
@property (nonatomic) NSIndexPath *indexPathToDelete;
@end

@implementation CBIDeleteFolderConfirmationAlertView
@end

@interface CBIFolderViewModel () <UIAlertViewDelegate, UIActionSheetDelegate>
@property (nonatomic, strong) UIBarButtonItem *addItem;
@property (nonatomic, strong) ToastManager *toastManager;
@end

@implementation CBIFolderViewModel

- (id)init
{
    self = [super init];
    if (self) {
        self.toastManager = [ToastManager new];
        NSSortDescriptor *caseInsensitiveCompare = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES selector:@selector(localizedCaseInsensitiveCompare:)];
        self.collectionController = [MLVCCollectionController collectionControllerGroupingByBlock:nil groupTitleBlock:nil sortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"index" ascending:YES], caseInsensitiveCompare]];
        
        self.unlockedIcon = [[UIImage techDebtImageNamed:@"icon_folder"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        RAC(self, name) = RACObserve(self, model.name);
        RAC(self, lockedItemName) = RACObserve(self, model.name);
        RAC(self, viewControllerTitle) = RACObserve(self, model.name);
        
        @weakify(self);
        [RACObserve(self, model.context) subscribeNext:^(id x) {
            @strongify(self);
            if ([self.model.context isKindOfClass:[CKIGroup class]]) {
                self.canEdit = YES;
            } else {
                CKICourse *course = (CKICourse *)self.model.context;
                RAC(self, canEdit) = [RACObserve(course, enrollments) map:^id(NSArray *enrollments) {
                    BOOL isTeacherOrTA = [enrollments.rac_sequence any:^BOOL(CKIEnrollment *enrollment) {
                        // Only teachers and tas should be able to edit the folders for a course
                        return enrollment.type == CKIEnrollmentTypeTeacher || enrollment.type == CKIEnrollmentTypeTA || enrollment.type == CKIEnrollmentTypeDesigner;
                    }];
                    return @(isTeacherOrTA);
                }];
            }
        }];
        
        self.canEdit = NO;
    }
    return self;
}

- (void)viewController:(UIViewController *)viewController viewWillAppear:(BOOL)animated
{
    CKICourse *course = (CKICourse *)self.model.context;
    
    __block BOOL isTeacherOrTeachingAssistant = NO;
    
    if ([course respondsToSelector:@selector(enrollments)]) {
        [course.enrollments enumerateObjectsUsingBlock:^(CKIEnrollment *enrollment, NSUInteger idx, BOOL *stop) {
            if (enrollment.type == CKIEnrollmentTypeTeacher || enrollment.type == CKIEnrollmentTypeTA) {
                isTeacherOrTeachingAssistant = YES;
                *stop = YES;
            }
        }];
    }
    
    if (isTeacherOrTeachingAssistant || [course isKindOfClass:[CKIGroup class]]) {
        self.addItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(addButtonTouched:)];
        viewController.navigationItem.rightBarButtonItem = self.addItem;
    }
}

- (void)addButtonTouched:(UIBarButtonItem *)button
{
    self.addItem.enabled = NO;
    UIActionSheet *addActionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", "Cancel button title") destructiveButtonTitle:nil otherButtonTitles:NSLocalizedString(@"Add a folder", nil), NSLocalizedString(@"Upload a file", nil), nil];
    [addActionSheet showFromBarButtonItem:button animated:YES];
}

#pragma mark - action sheet delegate

- (void)actionSheet:(UIActionSheet *)actionSheet didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    self.addItem.enabled = YES;
    if (buttonIndex == 0) {
        UIAlertView *createAlertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"New Folder", nil) message:NSLocalizedString(@"Choose a name for the new folder", nil) delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", "Cancel button title") otherButtonTitles:@"Create Folder", nil];
        createAlertView.alertViewStyle = UIAlertViewStylePlainTextInput;
        [createAlertView show];
    } else if (buttonIndex == 1) {
        
        ReceivedFilesViewController *filesController = [ReceivedFilesViewController new];
        @weakify(filesController);
        filesController.submitButtonTitle = NSLocalizedString(@"Upload", @"Button title for uploading a file");
        filesController.onSubmitBlock = ^(NSArray *urls) {
            @strongify(filesController);
            [filesController dismissViewControllerAnimated:YES completion:^{
                if (urls.count == 0) {
                    return;
                }
                
                NSMutableArray *signalsArray = [NSMutableArray array];
                
                [self.toastManager statusBarToastInfo:[NSString stringWithFormat:@"Uploading File%@...", urls.count > 1 ? @"s" : @""] completion:nil];
                [urls enumerateObjectsUsingBlock:^(NSURL *fileURL, NSUInteger idx, BOOL *stop) {
                    NSString *extension = [[fileURL absoluteString] pathExtension];
                    NSData *fileData = [NSData dataWithContentsOfURL:fileURL options:NSDataReadingMappedIfSafe error:NULL];
                    
                    RACSignal *uploadSignal = [[CKIClient currentClient] uploadFile:fileData ofType:extension withName:[fileURL lastPathComponent] inFolder:self.model];
                    [signalsArray addObject:uploadSignal];
                }];
                
                @weakify(self);
                [[RACSignal merge:signalsArray] subscribeNext:^(CKIFile *newFile) {
                    @strongify(self);
                    CBIFileViewModel *fileViewModel = [[CBIFileViewModel alloc] init];
                    fileViewModel.model = newFile;
                    fileViewModel.index = 1;
                    fileViewModel.tintColor = self.tintColor;
                    [self.collectionController insertObjects:@[fileViewModel]];
                } error:^(NSError *error) {
                    @strongify(self);
                    [self.toastManager dismissNotification];
                } completed:^{
                    @strongify(self);
                    [self.toastManager dismissNotification];
                }];
            }];
        };
        filesController.modalPresentationStyle = UIModalPresentationFormSheet;
        
        UIWindow *window = [UIApplication sharedApplication].windows[0];
        [window.rootViewController presentViewController:filesController animated:YES completion:nil];
    }
}

#pragma mark - tableview delegate

- (BOOL)tableViewController:(MLVCTableViewController *)controller canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return self.canEdit;
}

- (void)tableViewController:(MLVCTableViewController *)tableViewController commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableViewController.viewModel.collectionController removeObjectAtIndexPath:indexPath];
    if (self == ((MLVCViewController *)[tableViewController.splitViewController.viewControllers objectAtIndex:1]).viewModel) {
        UINavigationController *emptyNav = [[UINavigationController alloc] initWithRootViewController:[[UIViewController alloc] init]];
        emptyNav.view.backgroundColor = [UIColor whiteColor];
        tableViewController.splitViewController.viewControllers = @[tableViewController.splitViewController.viewControllers[0], emptyNav];
    }
    
    RACSignal *deleteSignal = [[CKIClient currentClient] deleteFolder:self.model];
    
    @weakify(self);
    [deleteSignal subscribeError:^(NSError *error) {
        @strongify(self);
        [tableViewController.viewModel.collectionController insertObjects:@[self]];
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error deleting folder", @"Error deleting folder alert view title") message:error.localizedDescription delegate:nil cancelButtonTitle:NSLocalizedString(@"OK", nil) otherButtonTitles:nil];
        [alert show];
    }];
}

#pragma mark - alert view deleage

- (void)alertView:(CBIDeleteFolderConfirmationAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex) {
        CKIFolder *folder = [CKIFolder new];
        folder.name = [alertView textFieldAtIndex:0].text;
        [[[CKIClient currentClient] createFolder:folder InFolder:self.model] subscribeNext:^(CKIFolder *newFolder) {
            CBIFolderViewModel *folderViewModel = [[CBIFolderViewModel alloc] init];
            folderViewModel.model = newFolder;
            folderViewModel.index = 0;
            folderViewModel.tintColor = self.tintColor;
            [self.collectionController insertObjects:@[folderViewModel]];
        }];
    }
}

#pragma mark - syncing

- (RACSignal *)refreshViewModelsSignal {
    __block int count = 0;
    
    @weakify(self);
    
    RACSignal *foldersSignal = [[[CKIClient currentClient] fetchFoldersForFolder:self.model] map:^id(NSArray *folders) {
        return [[[folders rac_sequence] map:^id(CKIFolder *folder) {
            @strongify(self);
            CBIFolderViewModel *viewModel = [CBIFolderViewModel new];
            viewModel.index = count++;
            viewModel.model = folder;
            RAC(viewModel, tintColor) = RACObserve(self, tintColor);
            return viewModel;
        }] array];
    }];
    
    RACSignal *filesSignal = [[[CKIClient currentClient] fetchFilesForFolder:self.model] map:^id(NSArray *files) {
        return [[[files rac_sequence] map:^id(CKIFile *file) {
            @strongify(self);
            CBIFileViewModel *viewModel = [CBIFileViewModel new];
            viewModel.index = count++;
            viewModel.model = file;
            RAC(viewModel, tintColor) = RACObserve(self, tintColor);
            return viewModel;
        }] array];
    }];
    
    RACSignal *filesAndFoldersSignal = [RACSignal merge:@[foldersSignal, filesSignal]];
    return filesAndFoldersSignal;
}

@end
