#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MCPackSkinEntry : NSObject
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *textureFilename;
@property(nonatomic) BOOL isSlim;
@end

// Imports skins from Bedrock/Education Edition .mcpack skin packs (a zip
// containing manifest.json + skins.json + PNG textures) into the format
// read by the CustomSkinLoader Java mod's LocalSkinAPI, so a Java Edition
// account can wear a skin sourced from an .mcpack without any server-side
// support. Bedrock and Java use the same base humanoid UV layout, so a
// straight texture copy renders correctly for standard skins; .mcpack
// skins built on custom Bedrock geometry have no Java equivalent and are
// skipped.
@interface MCPackSkinImporter : NSObject

+ (nullable NSArray<MCPackSkinEntry *> *)listSkinsInPack:(NSString *)mcpackPath error:(NSError **)error;

+ (BOOL)installSkin:(MCPackSkinEntry *)entry
            fromPack:(NSString *)mcpackPath
         forUsername:(NSString *)username
           toGameDir:(NSString *)gameDir
               error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
