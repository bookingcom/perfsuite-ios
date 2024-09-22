@import FirebaseCrashlytics;

NS_ASSUME_NONNULL_BEGIN

/// We are using private function from Crashlytics to be able to record
/// custom exception without immediately sending it.
///
/// We will record stack trace for hang as fatal hang, and if it turned out 
/// to be a non-fatal hang, we will remove this Firebase report and replace it 
/// with non-fatal report.
///
/// We do not use recordExceptionModel here, because it doesn't return path 
/// to the report, so it is much harder to remove created report to re-create it 
/// with the different hang type.
NSString *FIRCLSExceptionRecordOnDemandModel(FIRExceptionModel *exceptionModel,
                                             int previousRecordedOnDemandExceptions,
                                             int previousDroppedOnDemandExceptions);

/// We need to pass proper type (first argument) to this method
/// to record stack traces of all the methods, 
/// that's why we cannot use public `FIRCLSExceptionRecordOnDemandModel`
NSString *FIRCLSExceptionRecordOnDemand(int type,
                                        const char *name,
                                        const char *reason,
                                        NSArray<FIRStackFrame *> *frames,
                                        BOOL fatal,
                                        int previousRecordedOnDemandExceptions,
                                        int previousDroppedOnDemandExceptions);


/// Firebase marker file which indicates that exception happened during the previous launch.
/// If this file is present: `FIRCrashlytics.didCrashDuringPreviousExecution` will be `YES` on the next launch.
extern const char *FIRCLSCrashedMarkerFileName;

/// This is FIRCLSFileManager, but this class is private.
/// We need to get rootPath to be able to remove marker file after we do recordOnDemandExceptionModel.
/// Because we do not want hangs to be considered as crashes in Crashlytics on the next launch.
@protocol RootPathProvider<NSObject>

@property(nonatomic, readonly, nullable) NSString *rootPath;

@end

@interface FIRCrashlytics (OnDemandException)

/// We use `recordOnDemandExceptionModel` instead of `recordExceptionModel`,
/// because `recordExceptionModel` will send data only on the next launch,
/// but we want to send non-fatal hang events as soon as we receive it.
- (void)recordOnDemandExceptionModel:(FIRExceptionModel *)exceptionModel;

/// We need file manager to get `rootPath` folder
@property(nonatomic, readonly, nullable) id<RootPathProvider> fileManager;

@end

NS_ASSUME_NONNULL_END
