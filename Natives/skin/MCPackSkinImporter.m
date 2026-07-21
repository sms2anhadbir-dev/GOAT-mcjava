#import <CoreGraphics/CoreGraphics.h>
#import <UIKit/UIKit.h>

#import "MCPackSkinImporter.h"
#import "UnzipKit.h"

static NSString *const kMCPackImporterErrorDomain = @"MCPackSkinImporterError";

@implementation MCPackSkinEntry
@end

@implementation MCPackSkinImporter

+ (nullable NSString *)skinsJsonPathInArchive:(UZKArchive *)archive error:(NSError **)error {
    NSArray<NSString *> *filenames = [archive listFilenames:error];
    if (!filenames) {
        return nil;
    }
    // skins.json is normally at the pack root, but some packs nest
    // everything under a single top-level folder; pick the shallowest match.
    NSString *best = nil;
    for (NSString *name in filenames) {
        if (![name.lastPathComponent isEqualToString:@"skins.json"]) {
            continue;
        }
        if (!best || name.pathComponents.count < best.pathComponents.count) {
            best = name;
        }
    }
    if (!best) {
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:1
                userInfo:@{NSLocalizedDescriptionKey: @"This .mcpack doesn't contain a skins.json - it isn't a skin pack."}];
        }
        return nil;
    }
    return best;
}

+ (nullable NSArray<MCPackSkinEntry *> *)listSkinsInPack:(NSString *)mcpackPath error:(NSError **)error {
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:mcpackPath error:error];
    if (!archive) {
        return nil;
    }

    NSString *skinsJsonPath = [self skinsJsonPathInArchive:archive error:error];
    if (!skinsJsonPath) {
        return nil;
    }

    NSData *jsonData = [archive extractDataFromFile:skinsJsonPath error:error];
    if (!jsonData) {
        return nil;
    }

    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:error];
    if (![root isKindOfClass:NSDictionary.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey: @"skins.json is malformed."}];
        }
        return nil;
    }

    NSArray *skins = root[@"skins"];
    if (![skins isKindOfClass:NSArray.class]) {
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:3
                userInfo:@{NSLocalizedDescriptionKey: @"skins.json has no skins array."}];
        }
        return nil;
    }

    NSMutableArray<MCPackSkinEntry *> *result = [NSMutableArray new];
    for (NSDictionary *skinDict in skins) {
        if (![skinDict isKindOfClass:NSDictionary.class]) continue;
        NSString *texture = skinDict[@"texture"];
        if (![texture isKindOfClass:NSString.class] || texture.length == 0) continue;

        MCPackSkinEntry *entry = [MCPackSkinEntry new];
        entry.textureFilename = texture;
        entry.isSlim = [skinDict[@"geometry"] isEqualToString:@"geometry.humanoid.customSlim"];
        NSString *localizationName = skinDict[@"localization_name"];
        entry.displayName = localizationName.length > 0 ? localizationName : texture.lastPathComponent.stringByDeletingPathExtension;
        [result addObject:entry];
    }

    if (result.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:4
                userInfo:@{NSLocalizedDescriptionKey: @"This pack doesn't contain any usable skins."}];
        }
        return nil;
    }

    return result;
}

// CustomSkinLoader's LocalSkinAPI auto-detects the Alex (slim) vs Steve
// (classic) model from the texture itself using the same "magic pixel"
// heuristic most Java skin tools use: an opaque pixel at (54,20) means
// classic, transparent means slim. Bedrock skin packs instead declare the
// model explicitly via `geometry`, so when the pack says slim we punch that
// pixel's alpha to 0 to force the same result client-side.
+ (nullable NSData *)pngData:(NSData *)pngData markedSlim:(BOOL)slim error:(NSError **)error {
    if (!slim) {
        return pngData;
    }

    UIImage *image = [UIImage imageWithData:pngData];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:5
                userInfo:@{NSLocalizedDescriptionKey: @"Skin texture is not a valid PNG."}];
        }
        return nil;
    }

    CGImageRef cgImage = image.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    if (width < 55 || height < 21) {
        // Not big enough to carry the slim-detection pixel; ship as-is.
        return pngData;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    size_t bytesPerRow = width * 4;
    uint8_t *pixels = calloc(height, bytesPerRow);
    CGContextRef ctx = CGBitmapContextCreate(pixels, width, height, 8, bytesPerRow, colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(colorSpace);
    if (!ctx) {
        free(pixels);
        if (error) {
            *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:6
                userInfo:@{NSLocalizedDescriptionKey: @"Failed to process skin texture."}];
        }
        return nil;
    }

    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);

    size_t offset = (20 * bytesPerRow) + (54 * 4);
    pixels[offset + 3] = 0; // alpha = 0

    CGImageRef resultImage = CGBitmapContextCreateImage(ctx);
    CGContextRelease(ctx);
    free(pixels);

    UIImage *finalImage = [UIImage imageWithCGImage:resultImage];
    CGImageRelease(resultImage);

    NSData *outData = UIImagePNGRepresentation(finalImage);
    if (!outData && error) {
        *error = [NSError errorWithDomain:kMCPackImporterErrorDomain code:7
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to re-encode skin texture."}];
    }
    return outData;
}

+ (BOOL)installSkin:(MCPackSkinEntry *)entry
            fromPack:(NSString *)mcpackPath
         forUsername:(NSString *)username
           toGameDir:(NSString *)gameDir
               error:(NSError **)error {
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:mcpackPath error:error];
    if (!archive) {
        return NO;
    }

    NSString *skinsJsonPath = [self skinsJsonPathInArchive:archive error:error];
    if (!skinsJsonPath) {
        return NO;
    }
    NSString *packRoot = skinsJsonPath.stringByDeletingLastPathComponent;
    NSString *texturePath = packRoot.length > 0
        ? [packRoot stringByAppendingPathComponent:entry.textureFilename]
        : entry.textureFilename;

    NSData *rawPng = [archive extractDataFromFile:texturePath error:error];
    if (!rawPng) {
        return NO;
    }

    NSData *finalPng = [self pngData:rawPng markedSlim:entry.isSlim error:error];
    if (!finalPng) {
        return NO;
    }

    NSString *skinDir = [gameDir stringByAppendingPathComponent:@"CustomSkinLoader/LocalSkin/skins"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:skinDir withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSString *destPath = [skinDir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", username]];
    return [finalPng writeToFile:destPath options:NSDataWritingAtomic error:error];
}

@end
