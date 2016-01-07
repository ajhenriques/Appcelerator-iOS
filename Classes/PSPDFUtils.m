//
//  PSPDFUtils.m
//  PSPDFKit-Titanium
//
//  Copyright (c) 2011-2015 PSPDFKit GmbH. All rights reserved.
//
//  THIS SOURCE CODE AND ANY ACCOMPANYING DOCUMENTATION ARE PROTECTED BY AUSTRIAN COPYRIGHT LAW
//  AND MAY NOT BE RESOLD OR REDISTRIBUTED. USAGE IS BOUND TO THE PSPDFKIT LICENSE AGREEMENT.
//  UNAUTHORIZED REPRODUCTION OR DISTRIBUTION IS SUBJECT TO CIVIL AND CRIMINAL PENALTIES.
//  This notice may not be removed from this file.
//

#import "PSPDFUtils.h"
#import "TiUtils.h"

@implementation PSPDFUtils

+ (NSInteger)intValue:(id)args {
    return [self intValue:args onPosition:0];
}

+ (NSInteger)intValue:(id)args onPosition:(NSUInteger)position {
    NSInteger intValue = NSNotFound;

    if (position == 0 && [args isKindOfClass:NSNumber.class]) {
        intValue = [args intValue];
    }else if([args isKindOfClass:NSArray.class] && [args count] > position) {
        intValue = [args[position] intValue];
    }

    return intValue;
}

+ (UIColor *)colorFromArg:(id)arg {
    if ([arg isKindOfClass:NSArray.class] && [[arg firstObject] isEqual:@"clear"]) {
        return [UIColor clearColor];
    }else {
        return [[TiUtils colorValue:arg] color];
    }
}

// use KVO to apply options
+ (void)applyOptions:(NSDictionary *)options onObject:(id)object {
    if (!options || !object) return;

    __block BOOL isControllerNeedsReload = NO;
    // set options
    [options enumerateKeysAndObjectsUsingBlock:^(NSString *key, id obj, BOOL *stop) {
        @try {
            PSCLog(@"setting %@ to %@.", key, obj);

            // convert boolean to YES/NO
            if ([obj isEqual:@"YES"])    obj = @YES;
            else if([obj isEqual:@"NO"]) obj = @NO;

            // convert color
            if ([key rangeOfString:@"color" options:NSCaseInsensitiveSearch].length > 0) {
                obj = [[TiColor colorNamed:obj] color];
            }

            // special handling for toolbar
            if ([key hasSuffix:@"BarButtonItems"] && [obj isKindOfClass:NSArray.class]) {
                NSMutableArray *newArray = [NSMutableArray array];
                for (id arrayItem in obj) {
                    if ([arrayItem isKindOfClass:NSString.class]) {
                        if ([object respondsToSelector:NSSelectorFromString(arrayItem)]) {
                            [newArray addObject:[object valueForKey:arrayItem]];
                        }
                    } else {
                        id newArrayItem = arrayItem;
                        if (![arrayItem isKindOfClass:UIBarButtonItem.class] && [arrayItem respondsToSelector:@selector(barButtonItem)]) {
                            newArrayItem = [arrayItem performSelector:@selector(barButtonItem)];
                            // Try to retain the TIButton proxy.
                            if ([arrayItem respondsToSelector:@selector(rememberSelf)]) {
                                [arrayItem performSelector:@selector(rememberSelf)];
                                // Release proxy once `object` is deallocated.
                                // (Object will be the PSPDFViewController)
                                [object pspdf_addDeallocBlock:^{
                                    [arrayItem performSelector:@selector(forgetSelf)];
                                } owner:arrayItem];
                            }
                        }
                        [newArray addObject:newArrayItem];
                    }
                }
                obj = newArray;
            }

            // special case handling for annotation name list
            if ([key isEqual:@"editableAnnotationTypes"] && [obj isKindOfClass:NSArray.class]) {
                obj = [NSMutableSet setWithArray:obj];
            }

            else if ([key.lowercaseString hasSuffix:@"size"] && [obj isKindOfClass:NSArray.class] && [obj count] == 2) {
                obj = [NSValue valueWithCGSize:CGSizeMake([[obj objectAtIndex:0] floatValue], [[obj objectAtIndex:1] floatValue])];
            }
            
            else if ([key isEqual:@"navBarHidden"]) {
                // handled in -[ComPspdfkitView createControllerProxy]
                return;
            }

            PSCLog(@"Set %@ to %@", key, obj);

            if ([object respondsToSelector:NSSelectorFromString(key)]) {
                [object setValue:obj forKeyPath:key];
            } else {
                if ([object isKindOfClass:PSPDFViewController.class]) {
                    PSPDFViewController *ctrl = object;
                    // set value via PSPDFConfiguration
                    [ctrl updateConfigurationWithoutReloadingWithBuilder:^(PSPDFConfigurationBuilder *builder) {
                        @try {
                            [builder setValue:obj forKey:key];
                        }
                        @catch (NSException *exception) {
                            PSCLog(@"Warning! Unable to set %@ for %@.", obj, key);
                        }
                    }];
                    isControllerNeedsReload = YES;
                }
            }
        }
        @catch (NSException *exception) {
            PSCLog(@"Recovered from error while parsing options: %@", exception);
        }
    }];
    if (isControllerNeedsReload && [object isKindOfClass:PSPDFViewController.class]) {
        PSPDFViewController *ctrl = object;
        [ctrl reloadData];
    }
}

// be smart about path search
+ (NSArray *)resolvePaths:(id)filePaths {
    NSMutableArray *resolvedPaths = [NSMutableArray array];

    if ([filePaths isKindOfClass:[NSString class]]) {
        NSString *resolvedPath = [self resolvePath:(NSString *)filePaths];
        if(resolvedPath) [resolvedPaths addObject:resolvedPath];
    }else if([filePaths isKindOfClass:NSArray.class]) {
        for (NSString *filePath in filePaths) {
            NSString *resolvedPath = [self resolvePath:filePath];
            if(resolvedPath) [resolvedPaths addObject:resolvedPath];
        }
    }

    return resolvedPaths;
}

+ (NSString *)resolvePath:(NSString *)filePath {
    if (![filePath isKindOfClass:NSString.class]) return nil;
    
    // If this is a full path; don't try to replace any parts.
    if (filePath.isAbsolutePath) {
        return PSFixIncorrectPath(filePath);
    }

    NSString *pdfPath = filePath;
    NSFileManager *fileManager = [NSFileManager new];

    if (![fileManager fileExistsAtPath:filePath]) {
        // Convert to URL and back to cope with file://localhost paths
        NSURL *urlPath = [NSURL URLWithString:filePath];
        pdfPath = [urlPath path];
        //PSTiLog(@"converted: %@", urlPath.path);
        if (![fileManager fileExistsAtPath:pdfPath]) {
            // try application bundle
            pdfPath = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:filePath];

            // try documents directory
            if (![fileManager fileExistsAtPath:pdfPath]) {
                NSString *cacheFolder = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
                pdfPath = [cacheFolder stringByAppendingPathComponent:filePath];
                if (![fileManager fileExistsAtPath:pdfPath]) {
                    PSCLog(@"PSPDFKit Error: pdf '%@' could not be found. Searched native path, application bundle and documents directory.", filePath);
                }
            }
        }
    }
    return pdfPath;
}

+ (NSArray *)documentsFromArgs:(id)args {
    NSMutableArray *documents = [NSMutableArray array];

    // be somewhat intelligent about path search
    for (NSString *filePath in args) {
        if ([filePath isKindOfClass:NSString.class]) {
            NSString *pdfPath = [PSPDFUtils resolvePath:filePath];

            if (pdfPath.length && [[NSFileManager defaultManager] fileExistsAtPath:pdfPath]) {
                PSPDFDocument *document = [[PSPDFDocument alloc] initWithURL:[NSURL fileURLWithPath:pdfPath]];
                if (document) {
                    [documents addObject:document];
                }
            }
        }
    }
    return documents;
}

@end

void ps_dispatch_sync_if(dispatch_queue_t queue, BOOL sync, dispatch_block_t block) {
    sync ? dispatch_sync(queue, block) : block();
}

void ps_dispatch_async_if(dispatch_queue_t queue, BOOL async, dispatch_block_t block) {
    async ? dispatch_async(queue, block) : block();
}

void ps_dispatch_main_sync(dispatch_block_t block) {
    ps_dispatch_sync_if(dispatch_get_main_queue(), !NSThread.isMainThread, block);
}

void ps_dispatch_main_async(dispatch_block_t block) {
    ps_dispatch_async_if(dispatch_get_main_queue(), !NSThread.isMainThread, block);
}

BOOL PSIsIncorrectPath(NSString *path) {
    return [path hasPrefix:@"file://localhost"];
}

NSString *PSFixIncorrectPath(NSString *path) {
    // If string is wrongly converted from an NSURL internally (via description and not path), fix this problem silently.
    NSString *newPath = path;
    if (PSIsIncorrectPath(path)) newPath = ((NSURL *)[NSURL URLWithString:path]).path;
    return newPath;
}

UIView *PSViewInsideViewWithPrefix(UIView *view, NSString *classNamePrefix) {
    if (!view || classNamePrefix.length == 0) return nil;

    UIView *theView = nil;
    for (UIView *subview in view.subviews) {
        if ([NSStringFromClass(subview.class) hasPrefix:classNamePrefix] || [NSStringFromClass(subview.superclass) hasPrefix:classNamePrefix]) {
            return subview;
        }else {
            if ((theView = PSViewInsideViewWithPrefix(subview, classNamePrefix))) break;
        }
    }
    return theView;
}

#define PSPDF_SILENCE_CALL_TO_UNKNOWN_SELECTOR(expression) \
_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Warc-performSelector-leaks\"") \
expression \
_Pragma("clang diagnostic pop")

#define PSPDFWeakifyAs(object, weakName) typeof(object) __weak weakName = object

void (^pst_targetActionBlock(id target, SEL action))(id) {
    // If there's no target, return an empty block.
    if (!target) return ^(__unused id sender) {};

    NSCParameterAssert(action);

    // All ObjC methods have two arguments. This fails if either target is nil, action not implemented or else.
    NSUInteger numberOfArguments = [target methodSignatureForSelector:action].numberOfArguments;
    NSCAssert(numberOfArguments == 2 || numberOfArguments == 3, @"%@ should have at most one argument.", NSStringFromSelector(action));

    PSPDFWeakifyAs(target, weakTarget);
    if (numberOfArguments == 2) {
        return ^(__unused id sender) { PSPDF_SILENCE_CALL_TO_UNKNOWN_SELECTOR([weakTarget performSelector:action];) };
    } else {
        return ^(id sender) { PSPDF_SILENCE_CALL_TO_UNKNOWN_SELECTOR([weakTarget performSelector:action withObject:sender];) };
    }
}
