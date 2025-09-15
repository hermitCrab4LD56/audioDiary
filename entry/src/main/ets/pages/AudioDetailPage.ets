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
    this.deleteDialogController = new CustomDialogController({
      builder: DeleteConfirmDialog({
        fileName: this.audioRecord?.fileName || '',
        onConfirm: () => this.deleteAudioRecord(),
        onCancel: () => this.closeDeleteDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.deleteDialogController.open();
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
    try {
      if (!this.audioRecord) return;
      
      // 停止播放
      await this.stopPlayback();
      
      // 删除文件
      try {
        if (await fileIo.access(this.audioRecord.filePath)) {
          await fileIo.unlink(this.audioRecord.filePath);
        }
      } catch (fileError) {
        hilog.warn(DOMAIN, 'AudioDetailPage', `Failed to delete file: ${JSON.stringify(fileError)}`);
      }
      
      // 从数据库删除记录
      await this.databaseService.deleteAudioRecord(this.audioRecord.id);
      
      this.showToast('Deleted successfully');
      this.closeDeleteDialog();
      
      // 返回上一页
      setTimeout(() => {
        this.navigateBack();
      }, 1000);
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioDetailPage', `Failed to delete audio record: ${JSON.stringify(error)}`);
      this.showToast('Delete failed');
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
    if (this.deleteDialogController) {
      this.deleteDialogController.close();
      this.deleteDialogController = null;
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
    promptAction.showToast({
      message: message,
      duration: 2000
    });
  }

  /**
   * 返回上一页
   */
  private navigateBack(): void {
    router.back();
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
              Image($r('app.media.icon'))
                .width(20)
                .height(20)
                .fillColor('#333333')
            }
            .width(40)
            .height(40)
            .backgroundColor('transparent')
            .onClick(() => this.navigateBack())
            
            Text('音频详情')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .layoutWeight(1)
              .textAlign(TextAlign.Center)
            
            Button() {
              Image($r('app.media.icon'))
                .width(20)
                .height(20)
                .fillColor('#333333')
            }
            .width(40)
            .height(40)
            .backgroundColor('transparent')
            .onClick(() => {
              // 显示更多操作菜单
            })
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')

          // 音频信息卡片
          Column() {
            // 音频图标
            Column() {
              Image($r('app.media.icon'))
                .width(60)
                .height(60)
                .fillColor('#007AFF')
            }
            .width(120)
            .height(120)
            .backgroundColor('#F0F8FF')
            .borderRadius(60)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ bottom: 20 })
            
            // 文件名
            Text(this.audioRecord.fileName)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .textAlign(TextAlign.Center)
              .margin({ bottom: 8 })
            
            // 分组信息
            Text(`分组: ${this.getGroupName()}`)
              .fontSize(14)
              .fontColor('#666666')
              .margin({ bottom: 4 })
            
            // 创建时间
            Text(`创建于 ${this.formatDate(this.audioRecord.createTime)}`)
              .fontSize(14)
              .fontColor('#999999')
              .margin({ bottom: 4 })
            
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
          .margin({ top: 8, bottom: 8 })
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
            .margin({ bottom: 24 })
            
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
              
              // 播放/暂停按钮
              Button() {
                Image($r('app.media.icon'))
                  .width(32)
                  .height(32)
                  .fillColor('#FFFFFF')
              }
              .width(80)
              .height(80)
              .backgroundColor(this.playState === PlayState.PLAYING ? '#FF3B30' : '#007AFF')
              .borderRadius(40)
              .onClick(() => this.togglePlayPause())
              
              Blank()
              
              // 停止按钮
              Button() {
                Image($r('app.media.icon'))
                  .width(20)
                  .height(20)
                  .fillColor('#666666')
              }
              .width(60)
              .height(60)
              .backgroundColor('#F5F5F5')
              .borderRadius(30)
              .onClick(() => this.stopPlayback())
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            
            // 音量控制
            Row() {
              Image($r('app.media.icon'))
                .width(16)
                .height(16)
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
                .fontSize(12)
                .fontColor('#666666')
                .width(40)
                .textAlign(TextAlign.End)
                .margin({ left: 12 })
            }
            .width('100%')
            .margin({ top: 20 })
          }
          .width('100%')
          .padding(24)
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
            .margin({ bottom: 12 })
            
            Button('删除音频')
              .fontSize(16)
              .fontColor('#FF3B30')
              .backgroundColor('#FFF0F0')
              .borderRadius(8)
              .width('100%')
              .height(44)
              .onClick(() => this.showDeleteConfirmDialog())
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
      Text('删除音频')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      Text(`确定要删除"${this.fileName}"吗？`)
        .fontSize(16)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      
      Text('删除后无法恢复')
        .fontSize(14)
        .fontColor('#FF3B30')
        .textAlign(TextAlign.Center)
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
        
        Button('删除')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF3B30')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm();
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