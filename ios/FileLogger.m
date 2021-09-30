#import "FileLogger.h"

#define LOG_LEVEL_DEF ddLogLevel
#import <CocoaLumberjack/CocoaLumberjack.h>
#import <MessageUI/MessageUI.h>
#import "FileLoggerFormatter.h"
#import "CompressingLogFileManager.h"

enum LogLevel {
    LOG_LEVEL_DEBUG,
    LOG_LEVEL_INFO,
    LOG_LEVEL_WARNING,
    LOG_LEVEL_ERROR
};

static const DDLogLevel ddLogLevel = DDLogLevelDebug;

// try to use specific log context 
#define FL_LOG_CONTEXT 8765

#define FLLogError(frmt, ...)   LOG_MAYBE(NO,                ddLogLevel, DDLogFlagError,   FL_LOG_CONTEXT, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define FLLogWarn(frmt, ...)    LOG_MAYBE(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagWarning, FL_LOG_CONTEXT, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define FLLogInfo(frmt, ...)    LOG_MAYBE(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagInfo,    FL_LOG_CONTEXT, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define FLLogDebug(frmt, ...)   LOG_MAYBE(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagDebug,   FL_LOG_CONTEXT, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)
#define FLLogVerbose(frmt, ...) LOG_MAYBE(LOG_ASYNC_ENABLED, ddLogLevel, DDLogFlagVerbose, FL_LOG_CONTEXT, nil, __PRETTY_FUNCTION__, frmt, ##__VA_ARGS__)

/* ----------------------------------------------- */

@interface FileLogger () <MFMailComposeViewControllerDelegate>
@property (nonatomic, strong) DDFileLogger* fileLogger;
@end

@implementation FileLogger

RCT_EXPORT_MODULE()

- (dispatch_queue_t)methodQueue {
  return dispatch_get_main_queue();
}

RCT_EXPORT_METHOD(configure:(NSDictionary*)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSNumber* dailyRolling = options[@"dailyRolling"];
    NSNumber* maximumFileSize = options[@"maximumFileSize"];
    NSNumber* maximumNumberOfFiles = options[@"maximumNumberOfFiles"];
    NSString* logsDirectory = options[@"logsDirectory"];
    NSNumber* logFilesDiskQuota = options[@"logFilesDiskQuota"];
    
    //id<DDLogFileManager> fileManager = [[DDLogFileManagerDefault alloc] initWithLogsDirectory:logsDirectory];
    CompressingLogFileManager* fileManager = [[CompressingLogFileManager alloc] initWithLogsDirectory:logsDirectory];
    fileManager.maximumNumberOfLogFiles = [maximumNumberOfFiles unsignedIntegerValue];
    fileManager.logFilesDiskQuota = [logFilesDiskQuota unsignedIntegerValue];
    
    DDFileLogger* fileLogger = [[DDFileLogger alloc] initWithLogFileManager:fileManager];
    fileLogger.logFormatter = [[FileLoggerFormatter alloc] init];
    fileLogger.rollingFrequency = [dailyRolling boolValue] ? 24 * 60 * 60 : 0;
    fileLogger.maximumFileSize = [maximumFileSize unsignedIntegerValue];
    // do not cleanup other loggers - BackgroundGeolocation.Logger might be there
    // [DDLog removeAllLoggers];
    [DDLog addLogger:fileLogger];
    self.fileLogger = fileLogger;
    
    resolve(nil);
}

RCT_EXPORT_METHOD(write:(NSNumber* _Nonnull)level str:(NSString*)str) {
    switch (level.integerValue) {
        case LOG_LEVEL_DEBUG:
            //DDLogDebug(@"%@", str);
            FLLogDebug(@"%@", str);
            break;
        case LOG_LEVEL_INFO:
            //DDLogInfo(@"%@", str);
            FLLogInfo(@"%@", str);
            break;
        case LOG_LEVEL_WARNING:
            //DDLogWarn(@"%@", str);
            FLLogWarn(@"%@", str);
            break;
        case LOG_LEVEL_ERROR:
            //DDLogError(@"%@", str);
            FLLogError(@"%@", str);
            break;
    }
}

RCT_EXPORT_METHOD(getLogFilePaths:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    resolve(self.fileLogger.logFileManager.sortedLogFilePaths);
}

RCT_EXPORT_METHOD(deleteLogFiles:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    [self.fileLogger rollLogFileWithCompletionBlock:^{
        for (DDLogFileInfo* logFileInfo in [self.fileLogger.logFileManager unsortedLogFileInfos]) {
            if (logFileInfo.isArchived) {
                [[NSFileManager defaultManager] removeItemAtPath:logFileInfo.filePath error:nil];
            }
        }
        resolve(nil);
    }];
}

RCT_EXPORT_METHOD(sendLogFilesByEmail:(NSDictionary*)options resolver:(RCTPromiseResolveBlock)resolve rejecter:(RCTPromiseRejectBlock)reject) {
    NSString* to = options[@"to"];
    NSString* subject = options[@"subject"];
    NSString* body = options[@"body"];
    
    if (![MFMailComposeViewController canSendMail]) {
       reject(@"CannotSendMail", @"Cannot send emails on this device", nil);
       return;
    }
    
    MFMailComposeViewController* composeViewController = [[MFMailComposeViewController alloc] init];
    composeViewController.mailComposeDelegate = self;
    if (to) {
        [composeViewController setToRecipients:@[to]];
    }
    if (subject) {
        [composeViewController setSubject:subject];
    }
    if (body) {
        [composeViewController setMessageBody:body isHTML:NO];
    }
    
    NSArray<NSString*>* logFiles = self.fileLogger.logFileManager.sortedLogFilePaths;
    for (NSString* logFile in logFiles) {
        NSData* data = [NSData dataWithContentsOfFile:logFile];
        [composeViewController addAttachmentData:data mimeType:@"text/plain" fileName:[logFile lastPathComponent]];
    }
    
    UIViewController* presentingViewController = UIApplication.sharedApplication.delegate.window.rootViewController;
    while (presentingViewController.presentedViewController) {
        presentingViewController = presentingViewController.presentedViewController;
    }
    [presentingViewController presentViewController:composeViewController animated:YES completion:nil];
    
    resolve(nil);
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end

