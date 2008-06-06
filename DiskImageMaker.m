#import "DiskImageMaker.h"
#import "PipeReader.h"
#include <unistd.h>
#include <sys/param.h>
#include <sys/ucred.h>
#include <sys/mount.h>
	 
#define useLog 0

void setOutputToPipe(NSTask *task)
{
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[NSPipe pipe]];
}

void showTaskResult(NSTask *theTask)
{
	NSData * taskResult = [[[theTask standardOutput] fileHandleForReading] availableData];
	NSString * resultString = [[NSString alloc] initWithData:taskResult encoding:NSUTF8StringEncoding];
#if useLog
	NSLog(resultString);
#endif
	[resultString release];
}

id getTaskResult(NSTask *theTask)
{
#if useLog
	NSLog(@"start getTaskResult");
#endif
	NSData * taskResult = [[[theTask standardOutput] fileHandleForReading] availableData];
	NSString * resultString = [[NSString alloc] initWithData:taskResult encoding:NSUTF8StringEncoding];
#if useLog
	NSLog(resultString);
#endif
	id resultProp = [resultString propertyList];
	[resultString autorelease];
	return resultProp;
}

NSString *getTaskError(NSTask *theTask)
{
	NSData *taskResult = [[[theTask standardError] fileHandleForReading] availableData];
	NSString *resultString = [[NSString alloc] initWithData:taskResult encoding:NSUTF8StringEncoding];
	[resultString autorelease];
	return resultString;
}

@implementation DiskImageMaker

#pragma mark internal use
- (NSString *)uniqueName:(NSString *)baseName suffix:(NSString *)theSuffix location:(NSString *)dirPath;
{
	NSString *newName = [baseName stringByAppendingPathExtension:theSuffix];
	NSString *checkPath = [dirPath stringByAppendingPathComponent:newName];
	short i = 1;
	NSFileManager *myFileManager = [NSFileManager defaultManager];
	while ([myFileManager fileExistsAtPath:checkPath]){
		NSNumber *numberSuffix = [NSNumber numberWithShort:i++];
		newName = [[baseName stringByAppendingPathExtension:[numberSuffix stringValue]] stringByAppendingPathExtension:theSuffix];
		checkPath = [dirPath stringByAppendingPathComponent:newName];
	}
	return newName;	
}

- (NSString *)uniqueName:(NSString *)baseName location:(NSString*)dirPath;
{
	NSString * newName = [baseName stringByAppendingPathExtension:[dmgOptions dmgSuffix]];
	NSString * checkPath = [dirPath stringByAppendingPathComponent:newName];
	NSFileManager *myFileManager = [NSFileManager defaultManager];
	short i = 1;
	while ([myFileManager fileExistsAtPath:checkPath]){
		NSNumber * numberSuffix = [NSNumber numberWithShort:i++];
		newName = [[baseName stringByAppendingPathExtension:[numberSuffix stringValue]] 
									stringByAppendingPathExtension:[dmgOptions dmgSuffix]];
		checkPath = [workingLocation stringByAppendingPathComponent:newName];
	}
	return newName;
}

- (void)setSourceEnumerator:(NSEnumerator *)enumerator
{
	[enumerator retain];
	[sourceEnumerator release];
	sourceEnumerator = enumerator;
}

#pragma mark init and dealloc
- (id) init
{
	[super init];
	requireSpaceRatio = 1.0;
	myNotiCenter = [NSNotificationCenter defaultCenter];
	isReplacing = NO;
	expectedCompressRatio = 0.7;
	isAttached = NO;
	return self;
}

- (id)initWithSourceItem:(NSDocument<DMGDocument> *)anItem
{
	[self init];
	sourceItems = [[NSArray arrayWithObject:anItem] retain];
	NSString *source_path = [anItem fileName];
	
	if ([[[NSWorkspace sharedWorkspace] mountedLocalVolumePaths] containsObject:source_path]) {
		[self setWorkingLocation:[NSSearchPathForDirectoriesInDomains(NSDesktopDirectory, NSUserDomainMask, YES) lastObject]];
	} else {				
		[self setWorkingLocation:[source_path stringByDeletingLastPathComponent]];
	}
	
	NSString *source_name = [source_path lastPathComponent];
	if ((![anItem isFolder]) || [anItem isPackage]) {
		[self setDiskName:[source_name stringByDeletingPathExtension]];
	} else {
		[self setDiskName:source_name];
	}
	return self;
}

- (id)initWithSourceItems:(NSArray *)array
{
	[self init];
	sourceItems = [array retain];
	return self;
}

- (void)dealloc
{
	[sourceDmgPath release];
	[mountPoint release];
	[devEntry release];
	[terminationMessage release];
	[workingLocation release];
	[diskName release];
	[tmpDir release];
	[sourceItems release];
	[super dealloc];
}

#pragma mark setup methods
- (void)setDMGOptions:(id<DMGOptions>)anObject
{
	[anObject retain];
	[dmgOptions release];
	dmgOptions = anObject;
}

- (void)setDestination:(NSString *)aPath replacing:(BOOL)aFlag;
{
	[self setWorkingLocation:[aPath stringByDeletingLastPathComponent]];
	[self setDiskName:[[aPath lastPathComponent] stringByDeletingPathExtension]];
	isReplacing = aFlag;
	if (isReplacing) {
		[self setDmgName:[aPath lastPathComponent]];
	} else {
		[self setDmgName:[self uniqueName:diskName location:workingLocation]];
	}
}

- (NSString *)resolveDmgName
{
	[self setDmgName:[self uniqueName:diskName location:workingLocation]];
	return dmgName;
}

- (void)setCustomDmgName:(NSString *)theDmgName
{
	
	isReplacing = YES;
	[self setDmgName:theDmgName];
	[self setDiskName:[theDmgName stringByDeletingPathExtension]];
}

- (NSString *)dmgPath
{
	if (!dmgName) [self resolveDmgName];
	return [workingLocation stringByAppendingPathComponent:dmgName];
}

#pragma mark instance methods
- (BOOL)checkCondition:(NSWindowController<DMGWindowController> *)aWindowController
{
	if (![self checkWorkingLocationPermission]) {
		NSString* detailMessage = [NSString stringWithFormat:NSLocalizedString(@"No write permission",""),
			[self workingLocation]];
		[aWindowController showAlertMessage:NSLocalizedString(@"Insufficient access right.","") 
											withInformativeText:detailMessage];
		return NO;
	}
	
	if (![self checkFreeSpace]) {
		[aWindowController 
			showAlertMessage:NSLocalizedString(@"Can't progress jobs.","")
			withInformativeText:NSLocalizedString(@"Not enough free space for creating a disk image.", "")];
		return NO;
	}
	
	isOnlyFolder = NO;
	if ([sourceItems count] == 1) {
		isOnlyFolder = [[sourceItems lastObject] isFolder];
	}
	
	return YES;
}

- (BOOL)checkWorkingLocationPermission
{
#if useLog
	NSLog(@"start checkWorkingLocationPermission");
	NSLog(workingLocation);
#endif
	int wirtePermInt = access([workingLocation fileSystemRepresentation],02);
	return (wirtePermInt == 0);
}

- (BOOL) checkFreeSpace
{
	[self postStatusNotification: 
		NSLocalizedString(@"Checking free space of disks.","")];
		
	NSEnumerator *enumerator = [sourceItems objectEnumerator];
	sourceSize = 0;
	id <DMGDocument> anItem;
	while (anItem = [enumerator nextObject]) {
		sourceSize += [anItem fileSize];
	}
	//sourceSize += 500000;
	sourceSize += [[NSUserDefaults standardUserDefaults] integerForKey:@"additionalSize"];
	
	NSFileManager *myFileManager = [NSFileManager defaultManager];
	
	NSDictionary *infoWorkingDisk = [myFileManager fileSystemAttributesAtPath:workingLocation];
	unsigned long long freeSize = [[infoWorkingDisk objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
	NSString *dmg_format = [dmgOptions dmgFormat];
	self->willBeConverted = !([dmg_format isEqualToString:@"UDRW"]||[dmg_format isEqualToString:@"UDSP"]);
	
	if (willBeConverted) {
		[self setTmpDir:NSTemporaryDirectory()];
		NSDictionary *infoTmpDisk = [myFileManager fileSystemAttributesAtPath:tmpDir];
		
		if ([[infoTmpDisk objectForKey:NSFileSystemNumber] isEqualToNumber:[infoWorkingDisk objectForKey:NSFileSystemNumber]]) {
			requireSpaceRatio = 1 + expectedCompressRatio;
		}
		else {
			unsigned long long freeSizeTmpDir = [[infoTmpDisk objectForKey:@"NSFileSystemFreeSize"] unsignedLongLongValue];
			
			if (freeSizeTmpDir > sourceSize) {
				if ([dmg_format isEqualToString:@"UDZO"])
					requireSpaceRatio = expectedCompressRatio;
			}
			else {
				return NO;
			}
		}
	}
	else {
		requireSpaceRatio = 1;
	}
		
	if ( freeSize > requireSpaceRatio*sourceSize)
		return YES;
	else
		return NO;
}

#pragma mark disk image task
- (NSTask *)hdiUtilTask
{
	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:@"/usr/bin/hdiutil"];
	[task setCurrentDirectoryPath:workingLocation];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[NSPipe pipe]];
	return [task autorelease];
}

- (void) detachDiskImage:(NSNotification *)notification
{
#if useLog
	NSLog(@"start detachDiskImage");
#endif
	if (![self checkPreviousTask:notification]) {
		return;
	}
	
	[self postStatusNotification:NSLocalizedString(@"Detaching a disk image.","")];
	NSTask * dmgTask = [self hdiUtilTask];
	[dmgTask setArguments:[NSArray arrayWithObjects:@"detach",devEntry,nil]];

	if (willBeConverted) {
		[myNotiCenter addObserver:self selector:@selector(convertTmpDiskImage:) name:NSTaskDidTerminateNotification object:dmgTask];
	}
	else {
		if ([dmgOptions internetEnable]) {
			[myNotiCenter addObserver:self selector:@selector(internetEnable:) name:NSTaskDidTerminateNotification object:dmgTask];
		}
		else {
			[myNotiCenter addObserver:self selector:@selector(dmgTaskTerminate:) name:NSTaskDidTerminateNotification object:dmgTask];
		}
	}
	[self setCurrentTask:dmgTask];
	[dmgTask launch];
#if useLog
	showTaskResult(dmgTask);
	NSLog(@"end detachDiskImage");
#endif
}

- (void)deleteDSStore:(NSNotification *)notification
{
#if useLog
	NSLog(@"start deleteDSStore");
#endif
	if (![self checkPreviousTask:notification]) {
		return;
	}
	
	[self postStatusNotification:NSLocalizedString(@"Deleting .DS_Store files.","")];
	NSTask *task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:@"/usr/bin/find"];
	//[task setCurrentDirectoryPath:mountPoint];
	setOutputToPipe(task);
	[task setArguments:[NSArray arrayWithObjects:mountPoint, @"-name", @".DS_Store", @"-delete", nil]];
	
	[myNotiCenter addObserver:self selector:@selector(detachDiskImage:) name:NSTaskDidTerminateNotification object:task];

	[self setCurrentTask:task];
	[task launch];
}

NSString *mountPointForDevEntry(NSString *devEntry)
{
	struct statfs *buf;
	int i, count;
	const char *dev = [devEntry UTF8String];
	
	count = getmntinfo(&buf, 0);
	for (i=0; i<count; i++)
	{
		if (strcmp(buf[i].f_mntfromname, dev) == 0)
			return [NSString stringWithUTF8String:buf[i].f_mntonname];
	}
	return nil;
}

- (void) copySourceItems:(NSNotification *) notification
{
#if useLog
	NSLog(@"start copySourceItems:");
#endif
	if (![self checkPreviousTask:notification]) {
		return;
	}
	
	[self postStatusNotification: NSLocalizedString(@"Copying source files.","")];
	NSTask *previous_task = [notification object];
	
	if ([[previous_task launchPath] isEqualToString:@"/usr/bin/hdiutil"]) {
		NSDictionary *task_result = getTaskResult(previous_task);
#if useLog
		NSLog([task_result description]);
#endif
		task_result = [[task_result objectForKey:@"system-entities"] objectAtIndex:0];
		[self setDevEntry:[task_result objectForKey:@"dev-entry"]];
		[self setMountPoint:[task_result objectForKey:@"mount-point"]];
		[self setSourceEnumerator:[sourceItems objectEnumerator]];
	}
	
	NSDocument<DMGDocument>* source_item = [sourceEnumerator nextObject];
	if (!source_item) {
		if ([dmgOptions isDeleteDSStore]) {
			[self deleteDSStore:notification];
		}
		else {
			[self detachDiskImage:notification];
		}
		
		return;
	}

	if ([[dmgOptions filesystem] isEqualToString:@"HFS"]) {
		CFStringEncoding sysenc = CFStringGetSystemEncoding();
		NSTask *dt_task = [NSTask launchedTaskWithLaunchPath:@"/usr/sbin/disktool"
									arguments:[NSArray arrayWithObjects:@"-s",devEntry,
									[NSString stringWithFormat:@"%d",sysenc],  nil]];
		[dt_task waitUntilExit];
		// Fix volume name is not reflected if diskName have multi byte characters, 
		dt_task = [NSTask launchedTaskWithLaunchPath:@"/usr/sbin/diskutil"
									arguments:[NSArray arrayWithObjects:@"rename",devEntry, 
									diskName, nil]];
		[dt_task waitUntilExit];
		if ([dt_task terminationStatus] !=0) {
			NSLog(getTaskError(dt_task));
		}
		
		NSString *bufmp = mountPointForDevEntry(devEntry);
		if (bufmp) {
			[self setMountPoint:bufmp];
		} else {
			//NSLog([NSString stringWithFormat:@"Can't find the mount point for %@", devEntry]);
			terminationStatus = 1;
			[self setTerminationMessage:[NSString stringWithFormat:@"Can't find the mount point for %@", devEntry]];		
			[myNotiCenter postNotificationName: @"DmgDidTerminationNotification" object:self];
			return;
		}
		
		/*NSTask *hdiutil_info = [self hdiUtilTask];
		[hdiutil_info setArguments:[NSArray arrayWithObjects:@"info",@"-plist",nil]];
		PipeReader *reader = [PipeReader readerWithTask:hdiutil_info];
		[hdiutil_info launch];
		[hdiutil_info waitUntilExit];
		NSDictionary *mounted_dmgs = [[reader stdoutString] propertyList];
		NSEnumerator *enumerator = [[mounted_dmgs objectForKey:@"images"] objectEnumerator];
		NSDictionary *dmg_info;
		while (dmg_info = [enumerator nextObject]) {
			NSEnumerator *entities_enumerator = [[dmg_info objectForKey:@"system-entities"] objectEnumerator];
			NSDictionary *system_entity;
			while (system_entity = [entities_enumerator nextObject]) {
				if ([[system_entity objectForKey:@"dev-entry"] isEqualToString:devEntry]) {
					[self setMountPoint:[system_entity objectForKey:@"mount-point"]];
					break;
				}
			}
		}
		*/
	}
	
	NSTask * dittoTask = [[NSTask alloc] init];
	[dittoTask setLaunchPath:@"/usr/bin/ditto"];
	setOutputToPipe(dittoTask);
	
	NSString *copy_destination = mountPoint;
	
	if ([source_item isFolder]) {
		if ([source_item isPackage] || (!isOnlyFolder)) {
			copy_destination = [mountPoint stringByAppendingPathComponent:[[source_item fileName] lastPathComponent]];
		}
	}
	
	[dittoTask setArguments:[NSArray arrayWithObjects:@"--rsrc",[source_item fileName],copy_destination,nil]];
	[myNotiCenter addObserver:self selector:@selector(copySourceItems:) name:NSTaskDidTerminateNotification object:dittoTask];		
	
	[self setCurrentTask:[dittoTask autorelease]];
	[dittoTask launch];
#if useLog
	NSLog(@"end copySourceItems:");
#endif
}

- (void)internetEnable:(NSNotification *)notification
{
#if useLog
	NSLog(@"start internetEnable");
#endif	
	if (![self checkPreviousTask:notification]) {
		return;
	}

	[self postStatusNotification:NSLocalizedString(@"Setting internet-enable option.","")];
	NSTask * dmgTask = [self hdiUtilTask];
	[dmgTask setArguments:[NSArray arrayWithObjects:@"internet-enable",@"-yes", dmgName, nil]];

	[myNotiCenter addObserver:self selector:@selector(dmgTaskTerminate:) 
					name:NSTaskDidTerminateNotification object:dmgTask];
	[self setCurrentTask:dmgTask];
	[dmgTask launch];
#if useLog
	NSLog(@"end internetEnable");
#endif	
}

- (void) attachDiskImage: (NSNotification *) notification
{
#if useLog
	NSLog(@"start attachDiskImage");
#endif
	if (![self checkPreviousTask:notification]) {
		return;
	}
	
	[self postStatusNotification: NSLocalizedString(@"Attaching a disk image.","")];
	NSTask* dmgTask = [notification object];
	
	NSArray * resultArray = getTaskResult(dmgTask);
	NSString * dmgPath = [resultArray objectAtIndex:0];
	dmgTask = [self hdiUtilTask];
	
	[dmgTask setArguments:[NSArray arrayWithObjects:@"attach",dmgPath,@"-noverify",@"-nobrowse",@"-plist",nil]];
	
	[myNotiCenter addObserver:self selector:@selector(copySourceItems:) name:NSTaskDidTerminateNotification object:dmgTask];

	[self setCurrentTask:dmgTask];
	[dmgTask launch];
#if useLog
	NSLog(@"end attachDiskImage");
#endif
}

- (void) postStatusNotification: (NSString *) message
{
	NSDictionary* notifyInfo = [NSDictionary dictionaryWithObjectsAndKeys:message, @"statusMessage", nil];
	[[NSNotificationCenter defaultCenter] postNotificationName: @"DmgProgressNotification"
														object:self userInfo:notifyInfo];
}

- (void) createDiskImage
{
	NSDictionary * resultDict;
	NSString * imageSize;
	
	/*** make disk image file ***/
	if (sourceSize < 550000 ) 
		imageSize = @"550000";
	else 
		imageSize = [[NSNumber numberWithUnsignedLongLong:sourceSize] stringValue];
	
	[self postStatusNotification: NSLocalizedString(@"Creating a disk image.",
											"Status message of creating a disk image.")];
	
	NSTask * dmgTask = [self hdiUtilTask];
		
	NSString *dmg_type;

	if ([[dmgOptions dmgFormat] isEqualToString:@"UDSP"]) 
		dmg_type = @"SPARSE";
	else
		dmg_type = @"UDIF";
	
	NSString* dmg_target;
	if (willBeConverted) {
		//NSString *theSuffix = @"sparseimage";
		NSString *a_suffix = @"dmg";
		NSString *tmp_name = [self uniqueName:diskName suffix:a_suffix location:tmpDir];
#if useLog
		NSLog(tmp_name);
#endif
		dmg_target = [tmpDir stringByAppendingPathComponent:tmp_name];
		sourceDmgPath = [dmg_target retain];
	}
	else {
		dmg_target = dmgName;
	}
	
	if (isReplacing) {
		NSString *target_path = [workingLocation stringByAppendingPathComponent:dmgName];
		NSFileManager *file_manager = [NSFileManager defaultManager];
		if ([file_manager fileExistsAtPath:target_path]) {
			NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
			int tag;
			if (![workspace performFileOperation:NSWorkspaceRecycleOperation
									source:workingLocation destination:@""
									files:[NSArray arrayWithObject:dmgName] tag:&tag]) {
#if useLog
				NSLog(@"can not delete");
#endif
				[self setTerminationMessage:[NSString stringWithFormat:
					NSLocalizedString(@"The file \n %@ could not be removed.", 
									  "can not trash existing file"),
					target_path]];
				self->terminationStatus = 1;
				[myNotiCenter postNotificationName: @"DmgDidTerminationNotification" object:self];
				return;
			}
		}
	}
	
//	if (isSourceFolder) {
//		[dmgTask setArguments:[NSArray arrayWithObjects:@"create",@"-fs",@"HFS+",@" -srcfolder",sourcePath,@"-layout",@"None",@"-type",dmg_type,@"-volname",diskName,dmgTarget,@"-plist",nil]];
//	}
//	else {
//		[dmgTask setArguments:[NSArray arrayWithObjects:@"create",@"-fs",@"HFS+",@"-size",imageSize,@"-layout",@"None",@"-type",dmg_type,@"-volname",diskName,dmgTarget,@"-plist",nil]];
//	}
	NSString *fs = [dmgOptions filesystem];
	[dmgTask setArguments:[NSArray arrayWithObjects:@"create",@"-fs", fs,@"-size",imageSize,
									@"-layout",@"None",@"-type",dmg_type,@"-volname",diskName,
									dmg_target,@"-plist",nil]];
	
	[myNotiCenter addObserver:self selector:@selector(attachDiskImage:) 
									name:NSTaskDidTerminateNotification object:dmgTask];
	[self setCurrentTask:dmgTask];
	[dmgTask launch];
}

-(BOOL) checkPreviousTask:(NSNotification *)notification
{
#if useLog
	NSLog(@"start checkPreviousTask");
#endif

	NSTask *dmgTask = [notification object];
	
	[myNotiCenter removeObserver:self];
	
	if ([dmgTask terminationStatus] != 0) {
#if useLog
		NSLog(@"termination status is not 0");
#endif
		[self setTerminationMessage:getTaskError(dmgTask)];
		if ([terminationMessage endsWith:@".Trashes: Permission denied\n"]) {
#if useLog
			NSLog(@"success to delete .DS_Store");
#endif
			return YES;
		}
		else {
#if useLog
			NSLog(@"error occur");
#endif
			if (isAttached) {
				NSTask *detachTask = [self hdiUtilTask];
				[detachTask setArguments:[NSArray arrayWithObjects:@"detach",devEntry,nil]];
				[detachTask launch];
			}
			//[self dmgTaskTerminate: notification];
			terminationStatus = [dmgTask terminationStatus];
			[myNotiCenter postNotificationName: @"DmgDidTerminationNotification" object:self];
			return NO;
		}
	}
#if useLog	
	NSLog(@"termination status is 0");
#endif
	NSString *firstArg = [[dmgTask arguments] objectAtIndex:0];
	if ([firstArg isEqualToString:@"attach"]) {
		self->isAttached = YES;
	}
	else if ([firstArg isEqualToString:@"detach"]){
		self->isAttached = NO;
	}
#if useLog	
	NSLog(@"end checkPreviousTask");
#endif
	return YES;
}

-(void) convertTmpDiskImage:(NSNotification *)notification
{
#if useLog
	NSLog(@"start convertTmpDiskImage");
#endif
	if (![self checkPreviousTask:notification]) {
		return;
	}
	[self convertDiskImage];
}

-(void) convertDiskImage
{
#if useLog
	NSLog(@"start convertDiskImage");
#endif
	[self postStatusNotification: NSLocalizedString(@"Converting a disk image.","")];
	
	NSTask * dmgTask = [self hdiUtilTask];
	if (willBeConverted) 
		[myNotiCenter addObserver:self selector:@selector(deleteSourceDmg:) name:NSTaskDidTerminateNotification object:dmgTask];			
	else
		[myNotiCenter addObserver:self selector:@selector(dmgTaskTerminate:) name:NSTaskDidTerminateNotification object:dmgTask];
	
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"convert",
		sourceDmgPath, @"-format", [dmgOptions dmgFormat], @"-o",dmgName,@"-plist",nil];
	
	if ([[dmgOptions dmgFormat] isEqualToString:@"UDZO"]) {
		NSString *zlibLevelString = [NSString stringWithFormat:@"zlib-level=%i", [dmgOptions compressionLevel]+1];
		[arguments addObjectsFromArray:[NSArray arrayWithObjects:@"-imagekey" ,zlibLevelString ,nil]];
	}
	[dmgTask setArguments:arguments];
	[self setCurrentTask:dmgTask];
	[dmgTask launch];
#if useLog
	NSLog(@"end convertDiskImage");
#endif
}

-(void) deleteSourceDmg:(NSNotification *) notification
{
#if useLog
	NSLog(@"start deleteSourceDmg");
#endif
	NSFileManager *myFileManager = [NSFileManager defaultManager];
	[myFileManager removeFileAtPath:sourceDmgPath handler:nil];

	if ([self checkPreviousTask:notification]) {
		if ([dmgOptions internetEnable]) 
			[self internetEnable:notification];
		else
			[self dmgTaskTerminate:notification];
	}

#if useLog
	NSLog(@"end deleteSourceDmg");
#endif
}

- (void) dmgTaskTerminate:(NSNotification *)notification
{
#if useLog
	NSLog(@"start dmgTaskTerminate");
#endif
	NSTask *dmgTask = [notification object];
	terminationStatus = [dmgTask terminationStatus];
	if (terminationStatus) {
		[self setTerminationMessage:getTaskError(dmgTask)];
	}
	[myNotiCenter postNotificationName: @"DmgDidTerminationNotification" object:self];
#if useLog
	NSLog(@"end dmgTaskTerminate");
#endif
}

- (void)aboartTask
{
	[myNotiCenter removeObserver:self];
	[currentTask terminate];
	if (isAttached) {
		NSTask * dmgTask = [self hdiUtilTask];
		[dmgTask setArguments:[NSArray arrayWithObjects:@"detach",devEntry,nil]];
	}
	
	NSString *dmg_path = [workingLocation stringByAppendingPathComponent:dmgName];
	NSFileManager *file_manager = [NSFileManager defaultManager];
	if ([file_manager fileExistsAtPath:dmg_path]) {
		[file_manager removeFileAtPath:dmg_path handler:nil];
	}
	
	if ((willBeConverted) && ([file_manager fileExistsAtPath:sourceDmgPath])) {
		[file_manager removeFileAtPath:sourceDmgPath handler:nil];
	}
	
}

#pragma mark accessor methods

- (void)setMountPoint:(NSString *)theMountPoint
{
	[theMountPoint retain];
	[mountPoint release];
	mountPoint = theMountPoint;
}

- (void)setDevEntry:(NSString *)theDevEntry
{
	[theDevEntry retain];
	[devEntry release];
	devEntry = theDevEntry;
}

- (void)setCurrentTask:(NSTask *)aTask
{
	[aTask retain];
	[currentTask release];
	currentTask = aTask;
}

- (void)setTmpDir:(NSString *)path
{
	[path retain];
	[tmpDir release];
	tmpDir = path;
}

- (void)setDiskName:(NSString *)theDiskName
{
	[theDiskName retain];
	[diskName release];
	diskName = theDiskName;
}

- (void)setDmgName:(NSString *) theDmgName
{
	[theDmgName retain];
	[dmgName release];
	dmgName = theDmgName;
}

- (NSString *)dmgName
{
	return self->dmgName;
}

- (void)setTerminationMessage:(NSString *)theString
{
	[theString retain];
	[terminationMessage release];
	terminationMessage = theString;
}

- (NSString *)terminationMessage
{
	return self->terminationMessage;
}

- (int)terminationStatus
{
	return self->terminationStatus;
}

- (void)setWorkingLocation:(NSString *)theWorkingLocation
{
	[theWorkingLocation retain];
	[workingLocation release];
	workingLocation = theWorkingLocation;
}

- (NSString *)workingLocation
{
	return self->workingLocation;
}

- (void)setReplacing:(BOOL)aFlag
{
	isReplacing = aFlag;
}
@end

