#import <ObjFW/ObjFW.h>

#define HANAMI_SUCCESS 0
#define HANAMI_CONTINUE 1

@protocol HanamiPluginRequestContextProtocol
@property (nonatomic, strong) OFHTTPRequest *_Nonnull request;
@property (nonatomic, strong) OFStream *_Nullable requestBody;
@property (nonatomic, strong, getter=requestDataGetter) OFData *_Nullable requestData;
@property (nonatomic, readonly, getter=isStaticFileRequestGetter) BOOL isStaticFileRequest;
@property (nonatomic, strong) OFMutableDictionary *varMap;

+ (instancetype)contextFrom:(nonnull OFHTTPRequest *)request withRequestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response andVarMap:(nonnull OFMutableDictionary *)varMap;
- (BOOL)validateRequest;
- (void)setContentType:(nonnull OFString *)contentType;
- (void)setStatusCode:(int)statusCode;
- (void)setHeaders:(OFDictionary *)headers;
- (void)setObject:(nonnull id)object forKey:(nonnull id)key;
- (id)objectForKey:(nonnull id)key;
@end

@protocol HanamiRequestContextProtocol <HanamiPluginRequestContextProtocol>
@property (nonatomic, strong) OFHTTPResponse *response;
@end

@interface HanamiRequestContext : OFObject <HanamiRequestContextProtocol>
@property (nonatomic, strong) OFHTTPRequest *_Nonnull request;
@property (nonatomic, strong) OFStream *_Nullable requestBody;
@property (nonatomic, strong, getter=requestDataGetter) OFData *_Nullable requestData;
@property (nonatomic, strong) OFHTTPResponse *_Nonnull response;
@property (nonatomic, readonly, getter=isStaticFileRequestGetter) BOOL isStaticFileRequest;
@property (nonatomic, strong) OFMutableDictionary *varMap;

+ (instancetype)contextFrom:(nonnull OFHTTPRequest *)request withRequestBody:(nullable OFStream *)requestBody response:(nonnull OFHTTPResponse *)response andVarMap:(nonnull OFMutableDictionary *)varMap;
- (BOOL)validateRequest;
- (void)setContentType:(OFString *)contentType;
- (void)setStatusCode:(int)statusCode;
- (void)setHeaders:(OFDictionary *)headers;
- (void)setObject:(nonnull id)object forKey:(nonnull id)key;
- (id)objectForKey:(nonnull id)key;
@end