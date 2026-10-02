#import "HanamiEntry.h"
#import "HanamiUtils.h"
#import "HanamiConfig.h"
#import "HanamiPrivateConfig.h"

@implementation HanamiEntry

- (instancetype)initWithIRI:(OFIRI *)iri relativePath:(OFString *)relPath {
    self = [super init];
    if (![[OFFileManager defaultManager] fileExistsAtIRI:iri]) {
        OFLog(@"No file found at %@", iri);
        return nil;
    }
    self->_path = iri;
    self->_relPath = relPath;
    OFFileAttributes attributes = [[OFFileManager defaultManager] attributesOfItemAtIRI:iri];
    self->_modificationDate = [attributes valueForKey:OFFileModificationDate];
    self->_creationDate = [attributes valueForKey:OFFileCreationDate];
    return self;
}

- (OFString *)render:(OFString *)template varMap:(OFDictionary *)varMap {
    OFMutableDictionary *localVarMap = [varMap mutableCopy];
	OFString *contents;
	@try {
		contents = [[OFString alloc] initWithContentsOfIRI:self.path];
	} @catch (OFException *ex) {
		OFLog(@"Got Exception: %@", ex);
		return nil;
	}
    [localVarMap setValue:[OFString stringWithFormat:@"%s", month[self.modificationDate.localMonthOfYear - 1]] forKey:@"$mo"];
    [localVarMap setValue:[OFString stringWithFormat:@"%d", self.modificationDate.localDayOfMonth] forKey:@"$da"];
    [localVarMap setValue:[OFString stringWithFormat:@"%d", self.modificationDate.localYear] forKey:@"$yr"];

	size_t idx = [contents indexOfCharacterFromSet:[OFCharacterSet newlineCharacterSet]];

	OFString *first, *rest;
	if (idx != OFNotFound) {
		first = [contents substringWithRange:OFMakeRange(0, idx)];
		rest = [contents substringWithRange:OFMakeRange(idx + 1, contents.length - idx - 1)];
	} else {
		first = contents;
		rest = @"";
	}
	[localVarMap setValue:first forKey:@"$title"];
	[localVarMap setValue:rest forKey:@"$body"];
	[localVarMap setValue:[self.path.lastPathComponent stringByDeletingPathExtension] forKey:@"$fn"];
	// the reason we do the \\ to / is because on windows stringByDeletingLastPathComponent returns the appropriate path component divider for the runtime os
	[localVarMap setValue:[[self.relPath stringByDeletingLastPathComponent] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"] forKey:@"$path"];
    return [HanamiUtils transformTemplate:template varMap:localVarMap];
}

- (OFComparisonResult)compare:(nonnull HanamiEntry *)object {
    return [object.modificationDate compare:self.modificationDate];
}

+ (OFArray *)getEntriesAtIRI:(nonnull OFIRI *)iri {
	OFMutableArray *out = [[OFMutableArray alloc] init];
	OFArray *contents = [[OFFileManager defaultManager] contentsOfDirectoryAtIRI:iri];
	for (OFIRI *entryIRI in contents)
	    if ([[OFFileManager defaultManager] directoryExistsAtIRI:entryIRI])
			[out addObjectsFromArray:[self getEntriesAtIRI:entryIRI]];
        else if ([excluded containsObject:[HanamiUtils relativePathFrom:entriesPath to:entryIRI]])
			continue;
		else if (![[entryIRI pathExtension] isEqual:defaultFileExtension]) {
            OFLog(@"Hanami: Skipping file %@, because of expected extension mismatch", [entryIRI fileSystemRepresentation]);
	        continue;
		} else {
			HanamiEntry *entry = [[HanamiEntry alloc] initWithIRI:entryIRI relativePath:[HanamiUtils relativePathFrom:entriesPath to:entryIRI]];
			if (entry)
				[out addObject:entry];
		}
	return out;
}

- (OFString *)description {
	return [[super description] stringByAppendingFormat:@" %@ %@ %@ %@", _path, _relPath, _modificationDate, _creationDate];
}

@end