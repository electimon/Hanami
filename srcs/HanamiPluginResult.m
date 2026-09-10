#import "HanamiPluginResult.h"
#import "HanamiUtils.h"

@implementation HanamiPluginResult
- (instancetype)initWithStatusCode:(int)statusCode title:(OFString *)title headers:(OFDictionary *)headers andBody:(OFString *)body {
    self = [super init];

    if (statusCode>199&&statusCode<300&&[headers objectForKey:@"Content-Type"] == nil) {
        OFLog(@"Hanami: Failed to construct HanamiPluginResult, did you forget to set Content-Type?");
        return nil;
    }

    _statusCode = statusCode;
    _headers = headers;
    _title = title;
    _body = body;
    return self;
}

- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType title:(OFString *)title andBody:(OFString *)body {
    return [self initWithStatusCode:statusCode title:title headers:@{@"Content-Type": contentType} andBody:body];
}

// for $raw
- (instancetype)initWithStatusCode:(int)statusCode headers:(OFDictionary *)headers {
    return [self initWithStatusCode:statusCode title:@"" headers:headers andBody:@""];
}

- (instancetype)initWithStatusCode:(int)statusCode contentType:(OFString *)contentType {
    return [self initWithStatusCode:statusCode headers:@{@"Content-Type": contentType}];
}

- (OFString *)contentType {
    return [_headers objectForKey: @"Content-Type"];
}

- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap {
    OFMutableDictionary *localVarMap = [varMap mutableCopy];

    // ideally eventually thisll be configurable, but for dynamic plugin stuff
    // we set the date to just the current date provided by the date plugin
    [localVarMap setValue:[[localVarMap valueForKey:@"$date::month"] substringToIndex:3] forKey:@"$mo"];
    [localVarMap setValue:[localVarMap valueForKey:@"$date::day_numerial"] forKey:@"$da"];
    [localVarMap setValue:[localVarMap valueForKey:@"$date::year"] forKey:@"$yr"];
	[localVarMap setValue:self.title forKey:@"$title"];
	[localVarMap setValue:self.body forKey:@"$body"];
	// [localVarMap setValue:[self.path.lastPathComponent stringByDeletingPathExtension] forKey:@"$fn"];
	// the reason we do the \\ to / is because on windows stringByDeletingLastPathComponent returns the appropriate path component divider for the runtime os
	// [localVarMap setValue:[[self.relPath stringByDeletingLastPathComponent] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] forKey:@"$path"];
    return [HanamiUtils transformTemplate:template varMap:localVarMap];
}
@end