#import <UIKit/UIKit.h>
#import "ModJarInspector.h"

NS_ASSUME_NONNULL_BEGIN

// Given any mod .jar, detects its loader (via ModJarInspector) and gets it
// running with as little manual work as possible:
//  - Fabric/Quilt: fully automated - resolves a compatible loader version
//    from the loader's own API, installs the version profile, and drops
//    the mod into mods/. No further action needed beyond picking the new
//    profile in-app.
//  - Forge/NeoForge: the mod is dropped into mods/ immediately (order
//    doesn't matter - Forge only needs it there by launch time), and the
//    existing Forge/NeoForge installer screen is opened pre-scrolled to the
//    detected Minecraft version, since Forge's real installer has to run
//    to patch the game - there is no static package to fetch instead.
//  - Unrecognized jars fall back to the existing "run this jar" flow
//    unchanged, since they might be a standalone installer/tool rather
//    than a mod.
@interface UniversalModInstaller : NSObject

+ (void)installModAtPath:(NSString *)jarPath presentingViewController:(UIViewController *)presenter;

@end

NS_ASSUME_NONNULL_END
