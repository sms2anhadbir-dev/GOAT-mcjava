#import <UIKit/UIKit.h>

@interface ForgeInstallViewController : UITableViewController
// Optional: pre-select a vendor ("Forge"/"NeoForge") and expand/scroll to a
// detected Minecraft version, so the user only has to tap "Install" once
// this pushes rather than hunting for the right entry themselves.
@property(nonatomic, copy) NSString *preselectedVendor;
@property(nonatomic, copy) NSString *preselectedMCVersion;
@end
