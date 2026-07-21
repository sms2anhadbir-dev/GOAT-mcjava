#import "ModJarInspector.h"
#import "UnzipKit.h"

@implementation ModJarInfo
@end

@implementation ModJarInspector

+ (nullable NSString *)firstVersionTokenIn:(NSString *)text {
    if (!text) return nil;
    NSError *error;
    // Matches things like 1.20.1, 1.20, 20.4.237 - the first dotted numeric
    // run in a version-range string ("[1.20,1.21)", ">=1.20.1 <1.21", ...).
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\d+(\\.\\d+){1,2}" options:0 error:&error];
    if (!regex) return nil;
    NSTextCheckingResult *match = [regex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];
    if (!match) return nil;
    return [text substringWithRange:match.range];
}

+ (nullable NSString *)stringByExtractingMinecraftVersionFromTomlText:(NSString *)toml {
    // Very small best-effort scan: find the dependency block that declares
    // modId="minecraft" and pull the versionRange from it. This is not a
    // real TOML parser - mods.toml is simple enough that a line/window scan
    // is reliable in practice for this one field.
    NSArray<NSString *> *lines = [toml componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    BOOL inMinecraftBlock = NO;
    for (NSString *rawLine in lines) {
        NSString *line = [rawLine stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if ([line containsString:@"modId"] && [line containsString:@"\"minecraft\""]) {
            inMinecraftBlock = YES;
            continue;
        }
        if (inMinecraftBlock && [line hasPrefix:@"["]) {
            // Entered a new TOML table without finding versionRange; give up on this block.
            inMinecraftBlock = NO;
        }
        if (inMinecraftBlock && [line containsString:@"versionRange"]) {
            NSString *version = [self firstVersionTokenIn:line];
            if (version) return version;
        }
    }
    return nil;
}

+ (ModJarInfo *)inspectJarAtPath:(NSString *)jarPath {
    ModJarInfo *info = [ModJarInfo new];

    NSError *error;
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jarPath error:&error];
    if (!archive) {
        return info;
    }

    NSArray<NSString *> *filenames = [archive listFilenames:&error] ?: @[];
    NSSet<NSString *> *fileSet = [NSSet setWithArray:filenames];

    if ([fileSet containsObject:@"fabric.mod.json"]) {
        info.vendor = ModLoaderVendorFabric;
        NSData *data = [archive extractDataFromFile:@"fabric.mod.json" error:nil];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSString *range = [json[@"depends"] isKindOfClass:NSDictionary.class] ? json[@"depends"][@"minecraft"] : nil;
        info.minecraftVersion = [self firstVersionTokenIn:range];
    } else if ([fileSet containsObject:@"quilt.mod.json"]) {
        info.vendor = ModLoaderVendorQuilt;
        NSData *data = [archive extractDataFromFile:@"quilt.mod.json" error:nil];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *depends = json[@"quilt_loader"][@"depends"];
        for (NSDictionary *dep in depends) {
            if ([dep[@"id"] isEqualToString:@"minecraft"]) {
                info.minecraftVersion = [self firstVersionTokenIn:dep[@"versions"]];
                break;
            }
        }
    } else if ([fileSet containsObject:@"META-INF/neoforge.mods.toml"]) {
        info.vendor = ModLoaderVendorNeoForge;
        NSData *data = [archive extractDataFromFile:@"META-INF/neoforge.mods.toml" error:nil];
        NSString *toml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
        info.minecraftVersion = [self stringByExtractingMinecraftVersionFromTomlText:toml ?: @""];
    } else if ([fileSet containsObject:@"META-INF/mods.toml"]) {
        NSData *data = [archive extractDataFromFile:@"META-INF/mods.toml" error:nil];
        NSString *toml = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"";
        // Modern NeoForge (1.20.2+) also ships a mods.toml as a compatibility
        // shim; loaderVersion references give it away when present.
        info.vendor = [toml.lowercaseString containsString:@"neoforge"] ? ModLoaderVendorNeoForge : ModLoaderVendorForge;
        info.minecraftVersion = [self stringByExtractingMinecraftVersionFromTomlText:toml];
    } else if ([fileSet containsObject:@"mcmod.info"]) {
        info.vendor = ModLoaderVendorForge;
        NSData *data = [archive extractDataFromFile:@"mcmod.info" error:nil];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSDictionary *first = [json isKindOfClass:NSArray.class] ? [json firstObject] : json[@"modList"][0];
        info.minecraftVersion = [self firstVersionTokenIn:first[@"mcversion"]];
    }

    return info;
}

@end
