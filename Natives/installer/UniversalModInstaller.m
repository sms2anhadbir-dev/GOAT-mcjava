#import "AFNetworking.h"
#import "UniversalModInstaller.h"
#import "FabricInstallViewController.h"
#import "FabricUtils.h"
#import "ForgeInstallViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherProfileEditorViewController.h"
#import "PLProfiles.h"
#import "ios_uikit_bridge.h"
#import "utils.h"

@interface UniversalModInstaller ()
+ (void)autoInstallFabricLikeForVendor:(NSString *)vendor mcVersion:(NSString *)mcVersion nav:(LauncherNavigationController *)nav;
@end

@implementation UniversalModInstaller

+ (void)presentNavigated:(UIViewController *)vc from:(UIViewController *)presenter {
    UINavigationController *navWrapper = [[UINavigationController alloc] initWithRootViewController:vc];
    [presenter presentViewController:navWrapper animated:YES completion:nil];
}

+ (nullable NSString *)copyModToModsFolder:(NSString *)jarPath error:(NSError **)error {
    NSString *modsDir = [NSString stringWithFormat:@"%s/mods", getenv("POJAV_GAME_DIR")];
    if (![NSFileManager.defaultManager createDirectoryAtPath:modsDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return nil;
    }
    NSString *destPath = [modsDir stringByAppendingPathComponent:jarPath.lastPathComponent];
    [NSFileManager.defaultManager removeItemAtPath:destPath error:nil];
    if (![NSFileManager.defaultManager copyItemAtPath:jarPath toPath:destPath error:error]) {
        return nil;
    }
    return destPath;
}

+ (void)installModAtPath:(NSString *)jarPath presentingViewController:(LauncherNavigationController *)nav {
    ModJarInfo *info = [ModJarInspector inspectJarAtPath:jarPath];

    NSError *copyError;
    if (![self copyModToModsFolder:jarPath error:&copyError]) {
        showDialog(localize(@"Error", nil), copyError.localizedDescription);
        return;
    }

    switch (info.vendor) {
        case ModLoaderVendorFabric:
        case ModLoaderVendorQuilt: {
            if (!info.minecraftVersion) {
                // Couldn't tell which Minecraft version this targets - fall
                // back to the manual picker rather than guessing wrong.
                FabricInstallViewController *vc = [FabricInstallViewController new];
                [self presentNavigated:vc from:nav];
                return;
            }
            [self autoInstallFabricLikeForVendor:(info.vendor == ModLoaderVendorQuilt) ? @"Quilt" : @"Fabric"
                mcVersion:info.minecraftVersion nav:nav];
            return;
        }
        case ModLoaderVendorForge:
        case ModLoaderVendorNeoForge: {
            ForgeInstallViewController *vc = [ForgeInstallViewController new];
            vc.preselectedVendor = (info.vendor == ModLoaderVendorNeoForge) ? @"NeoForge" : @"Forge";
            vc.preselectedMCVersion = info.minecraftVersion;
            [self presentNavigated:vc from:nav];
            if (info.minecraftVersion) {
                showDialog(localize(@"launcher.menu.execute_jar", nil),
                    [NSString stringWithFormat:@"Detected %@ for Minecraft %@. Your mod is already in the mods folder - just tap Install below.",
                        vc.preselectedVendor, info.minecraftVersion]);
            }
            return;
        }
        case ModLoaderVendorUnknown:
        default:
            // Not a recognizable mod (could be a standalone installer/tool
            // jar) - fall back to the existing "run this jar" behavior.
            [nav enterModInstallerWithPath:jarPath hitEnterAfterWindowShown:NO];
            return;
    }
}

+ (void)autoInstallFabricLikeForVendor:(NSString *)vendor mcVersion:(NSString *)mcVersion nav:(LauncherNavigationController *)nav {
    NSDictionary *endpoint = FabricUtils.endpoints[vendor];

    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    [manager GET:endpoint[@"loader"] parameters:nil headers:nil progress:nil
    success:^(NSURLSessionTask *task, NSArray<NSDictionary *> *loaderVersions) {
        NSDictionary *chosen;
        for (NSDictionary *entry in loaderVersions) {
            BOOL stable = entry[@"stable"] ? [entry[@"stable"] boolValue] : ![entry[@"version"] containsString:@"beta"];
            if (stable) {
                chosen = entry;
                break;
            }
        }
        chosen = chosen ?: loaderVersions.firstObject;
        if (!chosen) {
            showDialog(localize(@"Error", nil), [NSString stringWithFormat:@"No %@ loader versions available.", vendor]);
            return;
        }

        NSString *jsonURL = [NSString stringWithFormat:endpoint[@"json"], mcVersion, chosen[@"version"]];
        [manager GET:jsonURL parameters:nil headers:nil progress:nil
        success:^(NSURLSessionTask *task, NSDictionary *versionJson) {
            NSString *jsonPath = [NSString stringWithFormat:@"%1$s/versions/%2$@/%2$@.json", getenv("POJAV_GAME_DIR"), versionJson[@"id"]];
            [NSFileManager.defaultManager createDirectoryAtPath:jsonPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            NSError *error = saveJSONToFile(versionJson, jsonPath);
            if (error) {
                showDialog(localize(@"Error", nil), error.localizedDescription);
                return;
            }

            [localVersionList addObject:@{@"id": versionJson[@"id"], @"type": @"custom"}];

            LauncherProfileEditorViewController *vc = [LauncherProfileEditorViewController new];
            vc.profile = @{
                @"icon": endpoint[@"icon"],
                @"name": versionJson[@"id"],
                @"lastVersionId": versionJson[@"id"]
            }.mutableCopy;
            [nav pushViewController:vc animated:YES];
        } failure:^(NSURLSessionTask *op, NSError *error) {
            showDialog(localize(@"Error", nil), error.localizedDescription);
        }];
    } failure:^(NSURLSessionTask *op, NSError *error) {
        showDialog(localize(@"Error", nil), error.localizedDescription);
    }];
}

@end
