#import "../../srcs/HanamiPlugin.h"
#include <ObjFW/OFInvalidEncodingException.h>
#include <ObjFW/OFCharacterSet.h>
#include <ObjFW/OFMutableDictionary.h>
#include <ObjFW/OFString.h>
#include <ObjFW/OFSHA256Hash.h>
#import "../../srcs/HanamiPluginResult.h"
#import "../../srcs/HanamiConfig.h"

#import <ObjSQLite3/ObjSQLite3.h>

#define DEFAULT_CSRF_SECRET @"WiththefallofGeneonUSAsDVDsalesdepartment"

@interface GuestBookPlugin: OFObject <HanamiPlugin>
@end

Class HanamiPluginClass(void) {
    return [GuestBookPlugin class];
}

@implementation GuestBookPlugin {
    SL3Connection *dbConn;
    SL3PreparedStatement *dbFetchStatement;
    OFString *csrfSecret;
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
        self->dbConn = [[SL3Connection alloc] initWithIRI:[OFIRI fileIRIWithPath:@"state/guestbook.db"]];
    } @catch (SL3OpenFailedException *ex) {
        OFLog(@"GuestBookPlugin: Failed to open db at state/guestbook.db");
        return nil;
    }
    [self createTables];
    self->dbFetchStatement = [self->dbConn prepareStatement:@"SELECT name, message FROM entries ORDER BY id DESC;"];

    HanamiConfig *config = [HanamiConfig instanceFor:@"guestbook"];
    self->csrfSecret = [config valueForKey:@"csrfSecret" defaultValue:DEFAULT_CSRF_SECRET];
    if ([self->csrfSecret isEqual:DEFAULT_CSRF_SECRET])
        OFLog(@"GuestBookPlugin: Hey! You should define a csrf secret in configs/guestbook.ini...\nLike this!\n[guestbook]\ncsrfSecret = \"MySecret!\"");
    return self;
}

- (void)transformMap:(OFMutableDictionary *)varMap {
}

- (HanamiPluginResult *)handleDisplayRequest:(OFHTTPRequest *)request andVarMap:(OFMutableDictionary *)varMap {
    OFMutableArray *entries = [[OFMutableArray alloc] init];
    OFString *previousSuccess = nil;

    if (request.IRI.query != nil) {
        OFDictionary *params = [self getParamsFrom:request.IRI.query];
        previousSuccess = [params objectForKey:@"success"];
        // todo do something
    }

    OFHMAC *hmacObj = [[OFHMAC alloc] initWithHashClass:[OFSHA256Hash class] allowsSwappableMemory:YES];
    [hmacObj setKey:[self->csrfSecret cStringWithEncoding:OFStringEncodingUTF8] length:[self->csrfSecret cStringLengthWithEncoding:OFStringEncodingUTF8]];

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

    OFLog(@"Ret: %@", entries);

    OFString *time = [OFString stringWithFormat:@"%.0f", [[OFDate date] timeIntervalSince1970]];
    [hmacObj updateWithBuffer:[time cStringWithEncoding:OFStringEncodingUTF8] length:[time cStringLengthWithEncoding:OFStringEncodingUTF8]];
    [hmacObj calculate];

    OFData *digestData = [OFData dataWithItemsNoCopy:(void *)hmacObj.digest count:32 freeWhenDone:NO];

    OFString *body = [OFString stringWithFormat:@" \
        <h1>Renn's Guestbook</h1> \
            <form method=\"post\" action=\"/guestbook.submit\"> \
            <input type=\"hidden\" name=\"csrf_val\" value=\"%@\"> \
            <input type=\"hidden\" name=\"csrf_token\" value=\"%@\"> \
            <div> \
                <label for=\"name\">Name:</label> \
                <br> \
                <input type=\"text\" name=\"name\" id=\"name\" required> \
            </div> \
            <div> \
                <label for=\"message\">Message:</label> \
                <br> \
                <input type=\"text\" name=\"message\" id=\"message\" required> \
            </div> \
            <div aria-hidden=\"true\" style=\"position:absolute;left:-9999px;top:-9999px;height:0;overflow:hidden;\"> \
                <input type=\"text\" name=\"website\" tabindex=\"-1\" autocomplete=\"off\"> \
            </div> \
            <input type=\"submit\" value=\"Submit\"> \
        </form> \
        <h2>Entries:</h2> \
        <ul> \
        %@ \
        </ul> \
    ", time, [digestData stringByBase64Encoding], htmlEntries];
    return [[HanamiPluginResult alloc] initWithStatusCode:200 contentType:@"" title:@"Guestbook" andBody:body];
}

- (OFDictionary *)getParamsFrom:(OFString *)requestString {
    if (![requestString containsString:@"&"])
        return nil;
    OFArray *paramsArr = [requestString componentsSeparatedByString:@"&"];
    OFMutableDictionary *paramsDict = [[OFMutableDictionary alloc] init];
    for (OFString *param in paramsArr) {
        if (![param containsString:@"="])
            continue;
        OFArray *splitParam = [param componentsSeparatedByString:@"="];
        if ([splitParam count] != 2)
            continue; // not support any param string that has an = in the name or value, = is reserved for the separator sorry
            // although i suppose if either obj is empty itll still be a valid string? caller should check for nil
        [paramsDict setObject:[splitParam objectAtIndex:1] forKey:[splitParam firstObject]];
    }
    return paramsDict;
}

#define done(num) \
    return [[HanamiPluginResult alloc] initWithStatusCode:303 headers:@{@"Location": [OFString stringWithFormat:@"/guestbook.html?success=%d", num]}];

- (HanamiPluginResult *)handleSubmitRequest:(OFHTTPRequest *)request requestData:(OFData *)requestData andVarMap:(OFMutableDictionary *)varMap {
    OFString *postedString = [OFString stringWithData:requestData encoding:OFStringEncodingUTF8];
    OFLog(@"az: %@", postedString);

    if (![postedString containsString:@"&"])
        done(1);

    OFDictionary *extractedParams = [self getParamsFrom:postedString];
    if (extractedParams == nil)
        done(2);
    if ([extractedParams objectForKey:@"csrf_val"] == nil || [extractedParams objectForKey:@"csrf_token"] == nil || [extractedParams objectForKey:@"message"] == nil || [extractedParams objectForKey:@"name"] == nil)
        done(3);

    OFHMAC *hmacObj = [[OFHMAC alloc] initWithHashClass:[OFSHA256Hash class] allowsSwappableMemory:YES];
    [hmacObj setKey:[self->csrfSecret cStringWithEncoding:OFStringEncodingUTF8] length:[self->csrfSecret cStringLengthWithEncoding:OFStringEncodingUTF8]];

    OFString *csrfVal = [extractedParams objectForKey:@"csrf_val"];
    [hmacObj updateWithBuffer:[csrfVal cStringWithEncoding:OFStringEncodingUTF8] length:[csrfVal cStringLengthWithEncoding:OFStringEncodingUTF8]];
    [hmacObj calculate];

    OFData *digestData = [OFData dataWithItemsNoCopy:(void *)hmacObj.digest count:32 freeWhenDone:NO];
    // there has to be a better way or like a builtin function with objfw to do this 
    OFString *csrfToken = \
        [[[[extractedParams objectForKey:@"csrf_token"] stringByReplacingOccurrencesOfString:@"%3D" withString:@"="]
            stringByReplacingOccurrencesOfString:@"%2B" withString:@"+"] stringByReplacingOccurrencesOfString:@"%2F" withString:@"/"]; // its seriously evil

    if ([csrfToken isEqual:[digestData stringByBase64Encoding]]) {
        OFArray *items = [[OFArray alloc] initWithObjects:[[extractedParams objectForKey:@"name"] stringByXMLEscaping], [[extractedParams objectForKey:@"message"] stringByXMLEscaping], nil];
        SL3PreparedStatement *dbSubmitStatement = [self->dbConn prepareStatement:@"INSERT INTO entries (name, message) VALUES ($name, $message)"];
        [dbSubmitStatement bindWithArray:items];
        [dbSubmitStatement step];
    } else
        done(4);
    done(0);
}

- (HanamiPluginResult *)handleRequest:(OFHTTPRequest *)request requestData:(nullable OFData *)requestData andVarMap:(OFMutableDictionary *)varMap {
    if ([request.IRI.path isEqual:@"/guestbook.html"])
        return [self handleDisplayRequest:request andVarMap:varMap];
    if ([request.IRI.path isEqual:@"/guestbook.submit"] && requestData != nil)
        return [self handleSubmitRequest:request requestData:(OFData *)requestData andVarMap:varMap];
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