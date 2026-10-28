#import "../../srcs/HanamiPlugin.h"
#import "../../srcs/HanamiPluginResult.h"
#import "../../srcs/HanamiConfig.h"
#import "../../srcs/HanamiTemplateDefaults.h"
#import "../../srcs/HanamiUtils.h"

#import <ObjSQLite3/ObjSQLite3.h>

#define DEFAULT_CSRF_SECRET @"WiththefallofGeneonUSAsDVDsalesdepartment"
#define MAX_BODY_BYTES 32768
#define TOKEN_LIFETIME 3600

@interface GuestBookPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [GuestBookPlugin class];
}

@implementation GuestBookPlugin {
    SL3Connection *dbConn;
    OFString *csrfSecret;
    OFString *publicOrigin;
}

- (void)createTables {
    [dbConn executeStatement:@" \
        CREATE TABLE IF NOT EXISTS entries ( \
            id INTEGER PRIMARY KEY AUTOINCREMENT, \
            name TEXT, \
            message TEXT \
        ); \
    "];
}

- (instancetype)init {
    self = [super init];
    @try {
        self->dbConn = [[SL3Connection alloc] initWithIRI:[[HanamiUtils getStateDirectory:[self name]] IRIByAppendingPathComponent:@"guestbook.db"]];
    } @catch (SL3OpenFailedException *ex) {
        OFLog(@"GuestBookPlugin: Failed to open db at %@", [[HanamiUtils getStateDirectory:[self name]] IRIByAppendingPathComponent:@"guestbook.db"].fileSystemRepresentation);
        return nil;
    }
    [self createTables];

    HanamiConfig *config = [HanamiConfig instanceFor:@"guestbook"];
    self->csrfSecret = [config valueForKey:@"csrfSecret" defaultValue:@""];
    self->publicOrigin = [config valueForKey:@"publicOrigin" defaultValue:@""];
    // Fail closed: a public fallback key makes signatures forgeable.
    if ([self->csrfSecret isEqual:DEFAULT_CSRF_SECRET] || self->csrfSecret.length < 32 ||
        self->publicOrigin.length == 0) {
        OFLog(@"GuestBookPlugin: disabled; configure a random csrfSecret (at least 32 characters) and publicOrigin in configs/guestbook.ini");
        return nil;
    }
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
}

- (HanamiPluginResult *)handleDisplayRequest:(id<HanamiPluginRequestContextProtocol>)reqCtx {
    OFMutableArray *entries = [[OFMutableArray alloc] init];
    OFString *previousSuccess = nil;
    [reqCtx setObject:@"" forKey:@"$guestbook::response"];

    if (reqCtx.request.IRI.query != nil) {
        OFDictionary *params = [self getParamsFrom:reqCtx.request.IRI.query];
        previousSuccess = [params objectForKey:@"success"];
        if ([previousSuccess isEqual:@"0"])
            [reqCtx setObject:@"Thank you for submitting a message!" forKey:@"$guestbook::response"];
    }

    OFHMAC *hmacObj = [[OFHMAC alloc] initWithHashClass:[OFSHA256Hash class] allowsSwappableMemory:YES];
    [hmacObj setKey:[self->csrfSecret cStringWithEncoding:OFStringEncodingUTF8] length:[self->csrfSecret cStringLengthWithEncoding:OFStringEncodingUTF8]];

    SL3PreparedStatement *dbFetchStatement = [self->dbConn prepareStatement:@"SELECT name, message FROM entries ORDER BY id DESC LIMIT 100;"];
    while ([dbFetchStatement step]) {
        @try {
            OFArray *rowArr = [dbFetchStatement currentRowArray];
            [entries addObjectsFromArray:rowArr];
        } @catch (OFInvalidEncodingException *ex) {
            OFLog(@"GuestBookPlugin: is state/guestbook.db corrupt? cannot display entries!");
            // todo, visual display of this?
            return nil;
        }
    }

    OFMutableString *htmlEntries = [[OFMutableString alloc] init];

    bool flippy = false;
    for (OFString *str in entries) {
        if (!flippy)
            [htmlEntries appendString:[OFString stringWithFormat:@"<li><strong>%@", [str stringByXMLEscaping]]];
        else
            [htmlEntries appendString:[OFString stringWithFormat:@"</strong>: %@</li>", [str stringByXMLEscaping]]];
        flippy = !flippy;
    }

    OFString *time = [OFString stringWithFormat:@"%.0f", [[OFDate date] timeIntervalSince1970]];
    [hmacObj updateWithBuffer:[time cStringWithEncoding:OFStringEncodingUTF8] length:[time cStringLengthWithEncoding:OFStringEncodingUTF8]];
    [hmacObj calculate];

    OFData *digestData = [OFData dataWithItemsNoCopy:(void *)hmacObj.digest count:32 freeWhenDone:NO];

    [reqCtx setObject:@"guestbook" forKey:@"$fn"];
    [reqCtx setObject:time forKey:@"$guestbook::csrf_val"];
    [reqCtx setObject:[digestData stringByBase64Encoding] forKey:@"$guestbook::csrf_token"];
    [reqCtx setObject:htmlEntries forKey:@"$guestbook::entries"];
    OFString *body = [HanamiUtils transformTemplate:[HanamiUtils getSupportTemplate:@"guestbook" for:[self name]] varMap:reqCtx.varMap];
    return [[HanamiPluginResult alloc] initWithStatusCode:200 title:@"Guestbook" headers:@{@"Content-Type": (OFString *)HTMLContentType, @"Cache-Control": @"no-store"} andBody:body];
}

- (OFDictionary *)getParamsFrom:(OFString *)requestString {
    OFMutableDictionary *params = [OFMutableDictionary dictionary];
    @try {
        for (OFString *part in [requestString componentsSeparatedByString:@"&"]) {
            OFRange separator = [part rangeOfString:@"="];
            if (separator.location == OFNotFound)
                return nil;
            OFString *key = [[[part substringToIndex:separator.location]
                stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            OFString *value = [[[part substringFromIndex:separator.location + 1]
                stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding];
            if (key.length == 0 || [params objectForKey:key] != nil)
                return nil;
            [params setObject:value forKey:key];
        }
    } @catch (OFInvalidFormatException *ex) {
        return nil;
    } @catch (OFInvalidEncodingException *ex) {
        return nil;
    }
    return params;
}

#define done(num) \
    return [[HanamiPluginResult alloc] initWithStatusCode:303 headers:@{@"Location": [OFString stringWithFormat:@"/guestbook.html?success=%d", num]}];

- (HanamiPluginResult *)handleSubmitRequest:(id<HanamiPluginRequestContextProtocol>)reqCtx {
    // Origin is mandatory: timestamp signatures alone are public bearer tokens,
    // and are not bound to a browser session. Never derive this from Host.
    if (![[reqCtx.request.headers objectForKey:@"Origin"] isEqual:self->publicOrigin])
        return [[HanamiPluginResult alloc] initWithStatusCode:403 headers:@{}];
    OFString *contentType = [reqCtx.request.headers objectForKey:@"Content-Type"];
    if (![[[[[contentType componentsSeparatedByString:@";"] firstObject]
            stringByDeletingEnclosingWhitespaces] lowercaseString]
            isEqual:@"application/x-www-form-urlencoded"])
        return [[HanamiPluginResult alloc] initWithStatusCode:415 headers:@{}];
    OFData *data = [reqCtx requestDataWithLimit:MAX_BODY_BYTES];
    if (data == nil)
        done(6);
    if (data.count > MAX_BODY_BYTES / data.itemSize)
        return [[HanamiPluginResult alloc] initWithStatusCode:413 headers:@{}];
    OFDictionary *extractedParams;
    @try {
        extractedParams = [self getParamsFrom:[OFString stringWithData:data encoding:OFStringEncodingUTF8]];
    } @catch (OFInvalidEncodingException *ex) {
        done(2);
    }
    if (extractedParams == nil)
        done(2);
    if ([extractedParams objectForKey:@"csrf_val"] == nil || [extractedParams objectForKey:@"csrf_token"] == nil || [extractedParams objectForKey:@"message"] == nil || [extractedParams objectForKey:@"name"] == nil)
        done(3);

    OFString *name = [extractedParams objectForKey:@"name"];
    OFString *message = [extractedParams objectForKey:@"message"];
    if ([name stringByDeletingEnclosingWhitespaces].length == 0 || name.length > 100 ||
        [message stringByDeletingEnclosingWhitespaces].length == 0 || message.length > 2000)
        done(3);

    OFString *websitePot = [extractedParams objectForKey:@"website"];
    if (websitePot != nil && [websitePot length] > 0)
        // mmmm?
        done(5);

    OFHMAC *hmacObj = [[OFHMAC alloc] initWithHashClass:[OFSHA256Hash class] allowsSwappableMemory:YES];
    [hmacObj setKey:[self->csrfSecret cStringWithEncoding:OFStringEncodingUTF8] length:[self->csrfSecret cStringLengthWithEncoding:OFStringEncodingUTF8]];

    OFString *csrfVal = [extractedParams objectForKey:@"csrf_val"];
    @try {
        long long timestamp = csrfVal.longLongValue;
        long long now = (long long)[[OFDate date] timeIntervalSince1970];
        if (![[OFString stringWithFormat:@"%lld", timestamp] isEqual:csrfVal] ||
            timestamp < 0 || timestamp > now || now - timestamp > TOKEN_LIFETIME)
            done(4);
    } @catch (OFInvalidFormatException *ex) {
        done(4);
    } @catch (OFOutOfRangeException *ex) {
        done(4);
    }
    [hmacObj updateWithBuffer:[csrfVal cStringWithEncoding:OFStringEncodingUTF8] length:[csrfVal cStringLengthWithEncoding:OFStringEncodingUTF8]];
    [hmacObj calculate];

    OFData *digestData = [OFData dataWithItemsNoCopy:(void *)hmacObj.digest count:32 freeWhenDone:NO];
    OFString *csrfToken = [extractedParams objectForKey:@"csrf_token"];
    const unsigned char *actual = (const unsigned char *)[csrfToken UTF8String];
    OFString *expected = [digestData stringByBase64Encoding];
    const unsigned char *wanted = (const unsigned char *)[expected UTF8String];
    unsigned char difference = 0;
    if (csrfToken.UTF8StringLength != expected.UTF8StringLength)
        done(4);
    for (size_t i = 0; i < expected.UTF8StringLength; i++)
        difference |= actual[i] ^ wanted[i];
    if (difference == 0) {
        OFArray *items = [[OFArray alloc] initWithObjects:[extractedParams objectForKey:@"name"], [extractedParams objectForKey:@"message"], nil];
        SL3PreparedStatement *dbSubmitStatement = [self->dbConn prepareStatement:@"INSERT INTO entries (name, message) VALUES ($name, $message)"];
        [dbSubmitStatement bindWithArray:items];
        [dbSubmitStatement step];
        [self->dbConn executeStatement:@"DELETE FROM entries WHERE id < (SELECT id FROM entries ORDER BY id DESC LIMIT 1 OFFSET 9999)"];
    } else
        done(4);
    done(0);
}

- (HanamiPluginResult *)handleRequest:(id<HanamiPluginRequestContextProtocol>)reqCtx {
    if ([reqCtx.request.IRI.path isEqual:@"/guestbook.html"]) {
        if (reqCtx.request.method != OFHTTPRequestMethodGet)
            return [[HanamiPluginResult alloc] initWithStatusCode:405 headers:@{@"Allow": @"GET"}];
        return [self handleDisplayRequest:reqCtx];
    }
    if ([reqCtx.request.IRI.path isEqual:@"/guestbook.submit"]) {
        if (reqCtx.request.method != OFHTTPRequestMethodPost)
            return [[HanamiPluginResult alloc] initWithStatusCode:405 headers:@{@"Allow": @"POST"}];
        return [self handleSubmitRequest:reqCtx];
    }
    return nil;
}

- (OFString *)name {
    return @"GuestBookPlugin";
}

- (OFString *)author {
    return @"Renn";
}

- (OFString *)version {
    return @"1.0";
}

@end
