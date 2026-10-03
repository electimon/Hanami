#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiPluginResult.h"
#import "../../srcs/HanamiConfig.h"
#import "../../srcs/HanamiDynamicConfig.h"
#import "../../srcs/HanamiFileManager.h"
#import "../../srcs/HanamiUtils.h"

#import <Mayushii.h>

#include <math.h>

@interface IndexerPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [IndexerPlugin class];
}

@implementation IndexerPlugin

- (instancetype)init {
    self = [super init];
    [HanamiFileManager createDirectoryAndParents:[[HanamiConfig getConfigBasePath] IRIByAppendingPathComponent:@"pub"]];
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
}

- (OFIRI *)handleablePath:(OFIRI *)iri {
    if ([iri.percentEncodedPath hasPrefix:@"/pub/"] == NO)
        return nil;

    OFIRI *basePath = [HanamiConfig getConfigBasePath];
    OFIRI *standardPath = [basePath IRIByAppendingPathComponent:iri.path].IRIByStandardizingPath;
    if (![[standardPath fileSystemRepresentation] hasPrefix:[OFString stringWithFormat:@"%@/", basePath.fileSystemRepresentation]])
        return nil;

    return standardPath;
}

- (OFString *)getSizeString:(unsigned long long)size {
    const unsigned long long KB = 1000;
    const unsigned long long MB = KB * 1000;
    const unsigned long long GB = MB * 1000;

    if (size < MB)
        return [OFString stringWithFormat:@"%llu KB", size / KB];
    else if (size >= GB)
        return [OFString stringWithFormat:@"%.2f GB", (double)size / GB];

    return [OFString stringWithFormat:@"%llu MB", size / MB];
}

- (OFString *)buildListing:(OFIRI *)path {
    OFArray *filesList;
@try {
    filesList = [[OFFileManager defaultManager] contentsOfDirectoryAtIRI:path];
} @catch (OFOpenItemFailedException *ex) {
    return @"No files found."; // empty dir huh
}
    OFMutableString *ret = [[OFMutableString alloc] initWithString:@"<tr>" \
                            "<td class=\"name\"><a href=\"../\">../</a></td>" \
                           "</tr>"];
    for (OFIRI *file in filesList) {
        OFFileAttributes attributes = [[OFFileManager defaultManager] attributesOfItemAtIRI:file];
        OFLog(@"rawSize = %@", [attributes objectForKey:OFFileSize]);
        [ret appendString:[OFString stringWithFormat:
                            @"<tr>" \
                            "<td class=\"name\"><a href=\"%@\">%@</a></td>" \
                            "<td>%@</td>" \
                            "<td>%@</td>" \
                           "</tr>", \
            [file lastPathComponent],
            [file lastPathComponent],
            [[attributes objectForKey:OFFileModificationDate] localDateStringWithFormat:@"%Y-%m-%d"],
            [self getSizeString:[[attributes objectForKey:OFFileSize] unsignedLongLongValue]]
        ]];
    }

    return ret;
}

- (HanamiPluginResult *)handleRequest:(id<HanamiPluginRequestContextProtocol>)reqCtx {
    OFIRI *path;
    if ((path = [self handleablePath:reqCtx.request.IRI]) == nil)
        return nil;

    if ([[OFFileManager defaultManager] fileExistsAtIRI:path] == NO)
        return nil;

    OFFileAttributes attributes = [[OFFileManager defaultManager] attributesOfItemAtIRI:path];
    if ([[attributes objectForKey:OFFileType] isEqual:OFFileTypeRegular]) {
        [reqCtx setObject:[OFData dataWithContentsOfIRI:path] forKey:@"$raw"];
        return [[HanamiPluginResult alloc] initWithStatusCode:200 contentType:[MYMimeParser mimeTypeFor:[path pathExtension]]];
    }

    OFString *fsPath = path.fileSystemRepresentation;
    OFRange range = [fsPath rangeOfString:@"/pub"];
    [reqCtx setObject:[fsPath substringFromIndex:range.location] forKey:@"$path"];
    [reqCtx setObject:[self buildListing:path] forKey:@"$index_entries"];
    [reqCtx setObject:[self version] forKey:@"$version"];
    [reqCtx setObject:[HanamiUtils transformTemplate:[HanamiUtils getTemplateAtIRI:[pluginsSupportPath IRIByAppendingPathComponent:@"IndexerPlugin/default.template"] defaultValue:@""] varMap:reqCtx.varMap] forKey:@"$raw"];

    return [[HanamiPluginResult alloc] initWithStatusCode:200 contentType:@"text/html"];
}

- (OFString *)name {
    return @"IndexerPlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end