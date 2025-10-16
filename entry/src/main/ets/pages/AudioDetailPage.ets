import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { AudioRecord, AudioGroup, PlayState } from '../model/DataModel';
import { AudioPlayerService } from '../service/AudioPlayerService';
import { DatabaseService } from '../service/DatabaseService';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0000;

// 定义对话框偏移量接口
interface DialogOffset {
  dx: number;
  dy: number;
}

@Entry
@Component
struct AudioDetailPage {
  @State audioRecord: AudioRecord | null = null;
  @State playState: PlayState = PlayState.IDLE;
  @State currentPosition: number = 0;
  @State totalDuration: number = 0;
  @State volume: number = 50;
  @State playbackSpeed: number = 1.0;
  @State isLoading: boolean = true;
  @State isShowDeleteDialog: boolean = false;
  @State isShowRenameDialog: boolean = false;
  @State isShowGroupDialog: boolean = false;
  @State newFileName: string = '';
  @State availableGroups: AudioGroup[] = [];
  @State selectedGroupId: number = 0;
  
  private audioPlayerService = AudioPlayerService.getInstance();
  private databaseService = DatabaseService.getInstance();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private audioId: number = 0;
  private updateTimer: number | null = null;
  private deleteDialogController: CustomDialogController | null = null;
  private renameDialogController: CustomDialogController | null = null;
  private groupDialogController: CustomDialogController | null = null;

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, 'AudioDetailPage', 'Page aboutToAppear');
    
    // 获取传递的参数
    const params = router.getParams() as Record<string, number | string>;
    if (params && params['audioId']) {
      this.audioId = params['audioId'] as number;
      await this.initializePage();
    } else {
      this.showToast('Invalid audio ID');
      this.navigateBack();
    }
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, 'AudioDetailPage', 'Page aboutToDisappear');
    this.stopUpdateTimer();
    this.audioPlayerService.stop();
    this.closeAllDialogs();
  }

  /**
   * 初始化页面
   */
  private async initializePage(): Promise<void> {
    try {
      // 初始化数据库
      await this.databaseService.initDatabase(this.context);
      
      // 加载音频记录
      await this.loadAudioRecord();
      
      // 初始化播放器
      await this.initializePlayer();
      
      // 加载分组列表
      await this.loadGroups();
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to initialize page: ${JSON.stringify(error)}`);
      this.showToast('Failed to initialize page');
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载音频记录
   */
  private async loadAudioRecord(): Promise<void> {
    try {
      this.audioRecord = await this.databaseService.getAudioRecordById(this.audioId);
      if (!this.audioRecord) {
        this.showToast('Audio record does not exist');
        this.navigateBack();
        return;
      }
      
      this.newFileName = this.audioRecord.fileName;
      this.selectedGroupId = this.audioRecord.groupId || 0;
      
      hilog.info(DOMAIN, 'AudioDetailPage', `Loaded audio record: ${this.audioRecord.fileName}`);
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to load audio record: ${JSON.stringify(error)}`);
      this.showToast('Failed to load audio record');
    }
  }

  /**
   * 初始化播放器
   */
  private async initializePlayer(): Promise<void> {
    try {
      if (!this.audioRecord) return;
      
      // 设置状态变化回调
      this.audioPlayerService.setStateChangeCallback((state: PlayState) => {
        this.playState = state;
      });

      // 设置位置更新回调
      this.audioPlayerService.setPositionCallback((position: number) => {
        this.currentPosition = position;
      });

      // 设置时长回调
      this.audioPlayerService.setDurationCallback((duration: number) => {
        this.totalDuration = duration;
      });

      // 设置错误回调
      this.audioPlayerService.setErrorCallback((error: string) => {
        this.showToast(`Playback error: ${error}`);
      });

      // 准备播放
      await this.audioPlayerService.prepare(this.audioRecord.filePath);
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to initialize player: ${JSON.stringify(error)}`);
      this.showToast('Failed to initialize player');
    }
  }

  /**
   * 加载分组列表
   */
  private async loadGroups(): Promise<void> {
    try {
      this.availableGroups = await this.databaseService.getAllGroups();
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to load groups: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 播放/暂停
   */
  private async togglePlayPause(): Promise<void> {
    try {
      if (this.playState === PlayState.PLAYING) {
        await this.audioPlayerService.pause();
        this.stopUpdateTimer();
      } else {
        if (this.audioRecord?.filePath) {
          await this.audioPlayerService.play(this.audioRecord.filePath);
          this.startUpdateTimer();
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to toggle play/pause: ${JSON.stringify(error)}`);
      this.showToast('Playback failed');
    }
  }

  /**
   * 停止播放
   */
  private async stopPlayback(): Promise<void> {
    try {
      await this.audioPlayerService.stop();
      this.stopUpdateTimer();
      this.currentPosition = 0;
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to stop playback: ${JSON.stringify(error)}`);
      this.showToast('Stop playback failed');
    }
  }

  /**
   * 主播放按钮点击处理 - 类似录音页面的功能
   */
  private async handleMainPlayButton(): Promise<void> {
    try {
      switch (this.playState) {
        case PlayState.IDLE:
          // 开始播放
          if (this.audioRecord?.filePath) {
            await this.audioPlayerService.play(this.audioRecord.filePath);
            this.startUpdateTimer();
          }
          break;
        case PlayState.PLAYING:
          // 暂停播放
          await this.audioPlayerService.pause();
          this.stopUpdateTimer();
          break;
        case PlayState.PAUSED:
          // 恢复播放
          await this.audioPlayerService.resume();
          this.startUpdateTimer();
          break;
        case PlayState.STOPPED:
          // 重新开始播放
          if (this.audioRecord?.filePath) {
            await this.audioPlayerService.play(this.audioRecord.filePath);
            this.startUpdateTimer();
          }
          break;
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to handle main play button: ${JSON.stringify(error)}`);
      this.showToast('Playback control failed');
    }
  }

  /**
   * 获取播放按钮颜色 - 类似录音页面的颜色逻辑
   */
  private getPlayButtonColor(): string {
    switch (this.playState) {
      case PlayState.PLAYING:
        return '#FF3B30'; // 播放中：红色
      case PlayState.PAUSED:
        return '#FF9500'; // 暂停：橙色
      default:
        return '#007AFF'; // 其他状态：蓝色
    }
  }

  /**
   * 跳转到指定位置
   */
  private async seekTo(position: number): Promise<void> {
    try {
      await this.audioPlayerService.seekTo(position);
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to seek: ${JSON.stringify(error)}`);
      this.showToast('Seek failed');
    }
  }

  /**
   * 设置音量
   */
  private async setVolume(volume: number): Promise<void> {
    try {
      this.volume = volume;
      await this.audioPlayerService.setVolume(volume / 100);
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to set volume: ${JSON.stringify(error)}`);
      this.showToast('Failed to set volume');
    }
  }

  /**
   * 设置播放速度
   */
  private async setPlaybackSpeed(speed: number): Promise<void> {
    try {
      this.playbackSpeed = speed;
      await this.audioPlayerService.setPlaybackSpeed(speed);
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to set playback speed: ${JSON.stringify(error)}`);
      this.showToast('Failed to set playback speed');
    }
  }

  /**
   * 显示删除确认对话框
   */
  private showDeleteConfirmDialog(): void {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🔔 showDeleteConfirmDialog() called`);
    
    if (!this.audioRecord) {
      hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ Cannot show delete dialog: audioRecord is null`);
      this.showToast('音频记录不存在');
      return;
    }
    
    hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 📝 准备删除的录音: '${this.audioRecord.fileName}'`);
    
    // 🔥 关键修复：使用正确的对话框创建方式（参照GroupPage的实现）
    const dialogController: CustomDialogController = new CustomDialogController({
      builder: DeleteConfirmDialog({
        fileName: this.audioRecord?.fileName || '',
        onConfirm: () => {
          hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 用户确认删除`);
          this.deleteAudioRecord();
        },
        onCancel: () => {
          hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 用户取消删除`);
          this.closeDeleteDialog();
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center,
      offset: { dx: 0, dy: 0 } as DialogOffset
    });
    
    this.deleteDialogController = dialogController;
    
    try {
      dialogController.open();
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 删除确认对话框已显示`);
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 显示删除对话框失败: ${JSON.stringify(error)}`);
      this.showToast('显示对话框失败');
    }
  }

  /**
   * 显示重命名对话框
   */
  private showRenameDialog(): void {
    this.newFileName = this.audioRecord?.fileName || '';
    this.renameDialogController = new CustomDialogController({
      builder: RenameDialog({
        fileName: this.newFileName,
        onConfirm: (name: string) => this.renameAudioRecord(name),
        onCancel: () => this.closeRenameDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.renameDialogController.open();
  }

  /**
   * 显示分组选择对话框
   */
  private showGroupSelectionDialog(): void {
    this.groupDialogController = new CustomDialogController({
      builder: GroupSelectionDialog({
        groups: this.availableGroups,
        selectedGroupId: this.selectedGroupId,
        onConfirm: (groupId: number) => this.moveToGroup(groupId),
        onCancel: () => this.closeGroupDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.groupDialogController.open();
  }

  /**
   * 删除音频记录
   */
  private async deleteAudioRecord(): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🗑️ deleteAudioRecord() started`);
    
    try {
      if (!this.audioRecord) {
        hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ audioRecord is null`);
        this.showToast('音频记录不存在');
        return;
      }
      
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 📊 准备删除录音: ID=${this.audioRecord.id}, 文件名='${this.audioRecord.fileName}'`);
      
      // 停止播放
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ⏹️ 停止播放`);
      await this.stopPlayback();
      
      // 删除文件
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 📁 删除文件: ${this.audioRecord.filePath}`);
      try {
        if (await fileIo.access(this.audioRecord.filePath)) {
          await fileIo.unlink(this.audioRecord.filePath);
          hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 文件删除成功`);
        } else {
          hilog.warn(DOMAIN, 'AudioDetailPage', `[${timestamp}] ⚠️ 文件不存在，跳过删除`);
        }
      } catch (fileError) {
        hilog.warn(DOMAIN, 'AudioDetailPage', `[${timestamp}] ⚠️ 文件删除失败: ${JSON.stringify(fileError)}`);
      }
      
      // 从数据库删除记录
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🗄️ 从数据库删除记录: ID=${this.audioRecord.id}`);
      await this.databaseService.deleteAudioRecord(this.audioRecord.id);
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 数据库记录删除成功`);
      
      // 验证删除是否成功
      const verifyRecord = await this.databaseService.getAudioRecordById(this.audioRecord.id);
      if (!verifyRecord) {
        hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 删除验证成功，记录已不存在`);
      } else {
        hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 删除验证失败，记录仍然存在`);
      }
      
      this.showToast('删除成功');
      this.closeDeleteDialog();
      
      // 立即返回上一页
      hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🏠 准备返回主页面`);
      this.navigateBack();
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 删除失败: ${JSON.stringify(error)}`);
      this.showToast('删除失败，请重试');
    }
  }

  /**
   * 重命名音频记录
   */
  private async renameAudioRecord(newName: string): Promise<void> {
    try {
      if (!this.audioRecord || !newName.trim()) {
        this.showToast('Please enter a valid filename');
        return;
      }
      
      const updatedRecord: AudioRecord = {
        id: this.audioRecord.id,
        fileName: newName.trim(),
        filePath: this.audioRecord.filePath,
        duration: this.audioRecord.duration,
        fileSize: this.audioRecord.fileSize,
        groupId: this.audioRecord.groupId,
        isTop: this.audioRecord.isTop,
        createTime: this.audioRecord.createTime
      } as AudioRecord;
      
      await this.databaseService.updateAudioRecord(updatedRecord);
      this.audioRecord = updatedRecord;
      
      this.showToast('Rename successful');
      this.closeRenameDialog();
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to rename audio record: ${JSON.stringify(error)}`);
      this.showToast('Rename failed');
    }
  }

  /**
   * 移动到分组
   */
  private async moveToGroup(groupId: number): Promise<void> {
    try {
      if (!this.audioRecord) return;
      
      const updatedRecord: AudioRecord = {
        id: this.audioRecord.id,
        fileName: this.audioRecord.fileName,
        filePath: this.audioRecord.filePath,
        duration: this.audioRecord.duration,
        fileSize: this.audioRecord.fileSize,
        groupId: groupId === 0 ? undefined : groupId,
        isTop: this.audioRecord.isTop,
        createTime: this.audioRecord.createTime
      } as AudioRecord;
      
      await this.databaseService.updateAudioRecord(updatedRecord);
      this.audioRecord = updatedRecord;
      this.selectedGroupId = groupId;
      
      const groupName = groupId === 0 ? 'Ungrouped' : 
        this.availableGroups.find(g => g.id === groupId)?.groupName || 'Unknown Group';
      
      this.showToast(`Moved to ${groupName}`);
      this.closeGroupDialog();
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to move to group: ${JSON.stringify(error)}`);
      this.showToast('Failed to move to group');
    }
  }

  /**
   * 关闭所有对话框
   */
  private closeAllDialogs(): void {
    this.closeDeleteDialog();
    this.closeRenameDialog();
    this.closeGroupDialog();
  }

  /**
   * 关闭删除对话框
   */
  private closeDeleteDialog(): void {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🔒 closeDeleteDialog() called`);
    
    if (this.deleteDialogController) {
      try {
        this.deleteDialogController.close();
        this.deleteDialogController = null;
        hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 删除对话框已关闭`);
      } catch (error) {
        hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 关闭删除对话框失败: ${JSON.stringify(error)}`);
      }
    }
  }

  /**
   * 关闭重命名对话框
   */
  private closeRenameDialog(): void {
    if (this.renameDialogController) {
      this.renameDialogController.close();
      this.renameDialogController = null;
    }
  }

  /**
   * 关闭分组对话框
   */
  private closeGroupDialog(): void {
    if (this.groupDialogController) {
      this.groupDialogController.close();
      this.groupDialogController = null;
    }
  }

  /**
   * 开始更新定时器
   */
  private startUpdateTimer(): void {
    this.stopUpdateTimer();
    this.updateTimer = setInterval(() => {
      // 定时器用于触发UI更新，实际数据通过回调更新
    }, 100);
  }

  /**
   * 停止更新定时器
   */
  private stopUpdateTimer(): void {
    if (this.updateTimer) {
      clearInterval(this.updateTimer);
      this.updateTimer = null;
    }
  }

  /**
   * 格式化时长
   */
  private formatDuration(duration: number): string {
    const totalSeconds = Math.floor(duration / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}`;
  }

  /**
   * 格式化日期
   */
  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    const hour = date.getHours().toString().padStart(2, '0');
    const minute = date.getMinutes().toString().padStart(2, '0');
    
    return `${year}-${month}-${day} ${hour}:${minute}`;
  }

  /**
   * 格式化文件大小
   */
  private formatFileSize(size: number): string {
    if (size < 1024) {
      return `${size} B`;
    } else if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)} KB`;
    } else {
      return `${(size / (1024 * 1024)).toFixed(1)} MB`;
    }
  }

  /**
   * 获取分组名称
   */
  private getGroupName(): string {
    if (!this.audioRecord?.groupId) {
      return 'Ungrouped';
    }
    
    const group = this.availableGroups.find(g => g.id === this.audioRecord?.groupId);
    return group?.groupName || 'Unknown Group';
  }

  /**
   * 显示提示信息
   */
  private showToast(message: string): void {
    try {
      promptAction.showToast({
        message: message,
        duration: 2000
      });
    } catch (error) {
      // 如果UI上下文不可用，只记录日志，不抛出异常
      hilog.warn(DOMAIN, 'AudioDetailPage', `Failed to show toast (UI context not available): ${message}`);
    }
  }

  /**
   * 返回上一页
   */
  private navigateBack(): void {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🏠 navigateBack() called`);
    
    // 使用setTimeout确保在当前UI事件处理完成后再执行导航
    setTimeout(() => {
      try {
        router.back();
        hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 页面返回成功`);
      } catch (error) {
        hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ 页面返回失败: ${JSON.stringify(error)}`);
        // 尝试使用replaceUrl作为备选方案
        try {
          router.replaceUrl({ url: 'pages/Index' });
          hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] ✅ 使用replaceUrl返回主页面成功`);
        } catch (replaceError) {
          hilog.error(DOMAIN, 'AudioDetailPage', `[${timestamp}] ❌ replaceUrl也失败: ${JSON.stringify(replaceError)}`);
        }
      }
    }, 100);
  }

  build() {
    Column() {
      if (this.isLoading) {
        // 加载状态
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color('#007AFF')
          
          Text('加载中...')
            .fontSize(14)
            .fontColor('#999999')
            .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F8F8F8')
      } else if (!this.audioRecord) {
        // 错误状态
        Column() {
          Image($r('app.media.icon'))
            .width(80)
            .height(80)
            .fillColor('#E5E5E5')
            .margin({ bottom: 16 })
          
          Text('音频记录不存在')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ bottom: 20 })
          
          Button('返回')
            .fontSize(16)
            .fontColor('#FFFFFF')
            .backgroundColor('#007AFF')
            .borderRadius(8)
            .width(100)
            .height(40)
            .onClick(() => this.navigateBack())
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#F8F8F8')
      } else {
        // 正常内容
        Column() {
          // 顶部导航栏
          Row() {
            Button() {
              Image($r('app.media.back_button'))
                .width(120)
                .height(70)
                .fillColor('#333333')
            }
            .width(120)
            .height(70)
            .backgroundColor('transparent')
            .onClick(() => this.navigateBack())
            
            Text('音频详情')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')

          // 音频信息卡片
          Column() {
            // 移除音频图标，保持布局间距
            // Row()
            // .width(20)
            // .height(20)
            // .margin({ bottom: 0 })
            
            // 文件名
            Text(this.audioRecord.fileName)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .margin({ bottom: 10 })
            
            // 分组信息
            Text(`分组: ${this.getGroupName()}`)
              .fontSize(14)
              .fontColor('#666666')
              .margin({ bottom: 8 })
            
            // 创建时间
            Text(`创建于 ${this.formatDate(this.audioRecord.createTime)}`)
              .fontSize(14)
              .fontColor('#999999')
              .margin({ bottom: 8 })
            
            // 文件大小和时长
            Row() {
              Text(`大小: ${this.formatFileSize(this.audioRecord.fileSize)}`)
                .fontSize(14)
                .fontColor('#999999')
              
              Text('|')
                .fontSize(14)
                .fontColor('#E5E5E5')
                .margin({ left: 12, right: 12 })
              
              Text(`时长: ${this.formatDuration(this.audioRecord.duration)}`)
                .fontSize(14)
                .fontColor('#999999')
            }
          }
          .width('100%')
          .padding(24)
          .backgroundColor('#FFFFFF')
          .margin({ top: 4, bottom: 4 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)

          // 播放控制区域
          Column() {
            // 进度条
            Column() {
              Row() {
                Text(this.formatDuration(this.currentPosition))
                  .fontSize(12)
                  .fontColor('#666666')
                
                Blank()
                
                Text(this.formatDuration(this.totalDuration))
                  .fontSize(12)
                  .fontColor('#666666')
              }
              .width('100%')
              .margin({ bottom: 8 })
              
              Slider({
                value: this.totalDuration > 0 ? (this.currentPosition / this.totalDuration) * 100 : 0,
                min: 0,
                max: 100,
                step: 1
              })
                .width('100%')
                .trackColor('#E5E5E5')
                .selectedColor('#007AFF')
                .blockColor('#007AFF')
                .onChange((value: number) => {
                  const position = (value / 100) * this.totalDuration;
                  this.seekTo(position);
                })
            }
            .width('100%')
            .margin({ bottom: 8 })
            
            // 播放控制按钮
            Row() {
              // 播放速度
              Button(`${this.playbackSpeed}x`)
                .fontSize(14)
                .fontColor('#007AFF')
                .backgroundColor('#F0F8FF')
                .borderRadius(20)
                .width(60)
                .height(40)
                .onClick(() => {
                  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
                  const currentIndex = speeds.indexOf(this.playbackSpeed);
                  const nextIndex = (currentIndex + 1) % speeds.length;
                  this.setPlaybackSpeed(speeds[nextIndex]);
                })
              
              Blank()
              
              // 主播放控制按钮
              Button() {
                Column() {
                  if (this.playState === PlayState.PLAYING) {
                    // 播放中显示暂停图标
                    Row()
                      .width(20)
                      .height(20)
                      .backgroundColor('#FFFFFF')
                      .borderRadius(2)
                  } else if (this.playState === PlayState.PAUSED) {
                    // 暂停状态显示播放图标
                    Circle()
                      .width(24)
                      .height(24)
                      .fill('#FFFFFF')
                  } else {
                    // 停止/空闲状态显示播放图标
                    Circle()
                      .width(24)
                      .height(24)
                      .fill('#FFFFFF')
                  }
                }
              }
              .width(70)
              .height(70)
              .backgroundColor(this.getPlayButtonColor())
              .borderRadius(40)
              .onClick(() => this.handleMainPlayButton())
              
              Blank()
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            
            // 音量控制
            Row() {
              Image($r('app.media.Audio'))
                .width(50)
                .height(50)
                .fillColor('#666666')
                .margin({ right: 12 })
              
              Slider({
                value: this.volume,
                min: 0,
                max: 100,
                step: 1
              })
                .layoutWeight(1)
                .trackColor('#E5E5E5')
                .selectedColor('#007AFF')
                .blockColor('#007AFF')
                .onChange((value: number) => {
                  this.setVolume(value);
                })
              
              Text(`${Math.round(this.volume)}%`)
                .fontSize(16)
                .fontColor('#666666')
                .width(40)
                .textAlign(TextAlign.End)
                .margin({ left: 12 })
            }
            .width('100%')
            .margin({ top: 20 })
          }
          .width('100%')
          .padding(21)
          .backgroundColor('#FFFFFF')
          .margin({ bottom: 8 })

          // 操作按钮区域
          Column() {
            Row() {
              Button('重命名')
                .fontSize(16)
                .fontColor('#007AFF')
                .backgroundColor('#F0F8FF')
                .borderRadius(8)
                .layoutWeight(1)
                .height(44)
                .onClick(() => this.showRenameDialog())
              
              Button('移动分组')
                .fontSize(16)
                .fontColor('#FF9500')
                .backgroundColor('#FFF8F0')
                .borderRadius(8)
                .layoutWeight(1)
                .height(44)
                .margin({ left: 12 })
                .onClick(() => this.showGroupSelectionDialog())
            }
            .width('100%')
            .margin({ bottom: 8 })
            
            Button('删除音频')
              .fontSize(16)
              .fontColor('#FF3B30')
              .backgroundColor('#FFF0F0')
              .borderRadius(8)
              .width('100%')
              .height(44)
              .onClick(() => {
                const timestamp = new Date().toISOString();
                hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🔘 删除音频按钮被点击`);
                this.showDeleteConfirmDialog();
              })
          }
          .width('100%')
          .padding(24)
          .backgroundColor('#FFFFFF')
        }
        .width('100%')
        .height('100%')
        .backgroundColor('#F8F8F8')
      }
    }
    .width('100%')
    .height('100%')
  }
}

// 删除确认对话框
@CustomDialog
struct DeleteConfirmDialog {
  fileName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      Column() {
        // 标题
        Text('删除音频')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 20 })
        
        // 提示文本
        Column() {
          Text(`确定要删除"${this.fileName}"吗？`)
            .fontSize(16)
            .fontColor('#666666')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ bottom: 8 })
          
          Text('删除后无法恢复')
            .fontSize(14)
            .fontColor('#FF3B30')
            .textAlign(TextAlign.Center)
            .width('100%')
        }
        .width('100%')
        .margin({ bottom: 30 })
        
        // 按钮区域
        Row() {
          Button() {
            Text('取消')
              .fontSize(16)
              .fontColor('#666666')
          }
          .fontSize(16)
          .fontColor('#666666')
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .width(100)
          .height(44)
          .onClick(() => {
            const timestamp = new Date().toISOString();
            hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🔘 对话框取消按钮被点击`);
            if (this.onCancel) {
              this.onCancel();
            }
          })
          
          Blank()
          
          Button() {
            Text('删除')
              .fontSize(16)
              .fontColor('#FFFFFF')
          }
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF3B30')
          .borderRadius(8)
          .width(100)
          .height(44)
          .onClick(() => {
            const timestamp = new Date().toISOString();
            hilog.info(DOMAIN, 'AudioDetailPage', `[${timestamp}] 🔘 对话框删除按钮被点击`);
            if (this.onConfirm) {
              this.onConfirm();
            }
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .padding(24)
      .backgroundColor('#FFFFFF')
      .borderRadius(16)
      .shadow({ radius: 16, color: '#00000030' })
    }
    .width(320)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

// 重命名对话框
@CustomDialog
struct RenameDialog {
  @State fileName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: (name: string) => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('重命名音频')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 20 })
      
      TextInput({ placeholder: '请输入新的文件名', text: this.fileName })
        .width('100%')
        .height(44)
        .backgroundColor('#F8F8F8')
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.fileName = value;
        })
      
      Row() {
        Button('取消')
          .fontSize(16)
          .fontColor('#666666')
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
        
        Blank()
        
        Button('保存')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#007AFF')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm(this.fileName);
            }
          })
      }
      .width('100%')
    }
    .width(300)
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}

// 分组选择对话框
@CustomDialog
struct GroupSelectionDialog {
  @State selectedGroupId: number = 0;
  groups: AudioGroup[] = [];
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: (groupId: number) => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('选择分组')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 20 })
      
      // 分组列表
      Column() {
        // 未分组选项
        Row() {
          Radio({ value: '0', group: 'group' })
            .checked(this.selectedGroupId === 0)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.selectedGroupId = 0;
              }
            })
          
          Text('未分组')
            .fontSize(16)
            .fontColor('#333333')
            .margin({ left: 12 })
            .layoutWeight(1)
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.selectedGroupId = 0;
        })
        
        // 分组选项
        ForEach(this.groups, (group: AudioGroup) => {
          Row() {
            Radio({ value: group.id.toString(), group: 'group' })
              .checked(this.selectedGroupId === group.id)
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  this.selectedGroupId = group.id;
                }
              })
            
            Text(group.groupName)
              .fontSize(16)
              .fontColor('#333333')
              .margin({ left: 12 })
              .layoutWeight(1)
          }
          .width('100%')
          .height(44)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.selectedGroupId = group.id;
          })
        })
      }
      .width('100%')
      .height(200)
      .margin({ bottom: 20 })
      
      Row() {
        Button('取消')
          .fontSize(16)
          .fontColor('#666666')
          .backgroundColor('#F5F5F5')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onCancel) {
              this.onCancel();
            }
          })
        
        Blank()
        
        Button('确定')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#007AFF')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm(this.selectedGroupId);
            }
          })
      }
      .width('100%')
    }
    .width(320)
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}