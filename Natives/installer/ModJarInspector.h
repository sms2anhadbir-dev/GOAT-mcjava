#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, ModLoaderVendor) {
    ModLoaderVendorUnknown = 0,
    ModLoaderVendorFabric,
    ModLoaderVendorQuilt,
    ModLoaderVendorForge,
    ModLoaderVendorNeoForge,
};

@interface ModJarInfo : NSObject
@property(nonatomic) ModLoaderVendor vendor;
// Best-effort guess, e.g. "1.20.1". Nil if it couldn't be determined from
// the jar's own metadata (loader manifests use free-form version ranges,
// not always a single pinned version).
@property(nonatomic, copy, nullable) NSString *minecraftVersion;
@end

// Detects which mod loader a .jar targets (Fabric/Quilt/Forge/NeoForge) and,
// on a best-effort basis, which Minecraft version - by reading the loader's
// own metadata file out of the jar (fabric.mod.json, quilt.mod.json,
// META-INF/mods.toml, META-INF/neoforge.mods.toml, or legacy mcmod.info).
// This is purely local static inspection; it does not talk to the network.
@interface ModJarInspector : NSObject

+ (ModJarInfo *)inspectJarAtPath:(NSString *)jarPath;

@end

NS_ASSUME_NONNULL_END
