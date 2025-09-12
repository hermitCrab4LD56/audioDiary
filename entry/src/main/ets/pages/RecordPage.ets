import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { RecordState, AudioRecord } from '../model/DataModel';
import { AudioRecordInput } from '../service/DatabaseService';
import { AudioRecorderService } from '../service/AudioRecorderService';
import { DatabaseService } from '../service/DatabaseService';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0000;

@Entry
@Component
struct RecordPage {
  @State recordState: RecordState = RecordState.IDLE;
  @State recordDuration: number = 0;
  @State fileName: string = '';
  @State isShowFileNameDialog: boolean = false;
  @State waveformData: number[] = [];
  @State currentAmplitude: number = 0;
  @State maxAmplitude: number = 100;
  @State isShowPermissionDialog: boolean = false;
  @State permissionMessage: string = '';
  @State isInitializing: boolean = false;
  
  private audioRecorderService = AudioRecorderService.getInstance();
  private databaseService = DatabaseService.getInstance();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private updateTimer: number | null = null;

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, 'RecordPage', 'Page aboutToAppear');
    await this.initializeRecorder();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, 'RecordPage', 'Page aboutToDisappear');
    this.stopUpdateTimer();
    this.audioRecorderService.release();
  }

  /**
   * 初始化录音器
   */
  private async initializeRecorder(): Promise<void> {
    this.isInitializing = true;
    
    try {
      hilog.info(DOMAIN, 'RecordPage', 'Starting recorder initialization...');
      
      // 初始化录音服务
      await this.audioRecorderService.initialize(this.context);
      
      // 设置状态变化回调
      this.audioRecorderService.setStateChangeCallback((state: RecordState) => {
        this.recordState = state;
        hilog.info(DOMAIN, 'RecordPage', `Record state changed to: ${state}`);
      });

      // 设置时长更新回调
      this.audioRecorderService.setDurationCallback((duration: number) => {
        this.recordDuration = duration;
      });

      // 设置振幅回调
      this.audioRecorderService.setAmplitudeCallback((amplitude: number) => {
        this.currentAmplitude = amplitude;
        this.updateWaveform(amplitude);
      });

      // 设置错误回调
      this.audioRecorderService.setErrorCallback((error: string) => {
        hilog.error(DOMAIN, 'RecordPage', `Recorder error: ${error}`);
        this.showToast(`录音错误: ${error}`);
      });

      // 初始化数据库
      await this.databaseService.initDatabase(this.context);
      
      hilog.info(DOMAIN, 'RecordPage', 'Recorder initialized successfully');
      this.showToast('录音器初始化成功');
      
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to initialize recorder: ${JSON.stringify(error)}`);
      
      const errorMessage = error instanceof Error ? error.message : String(error);
      
      // 检查是否是权限相关错误
      if (errorMessage.includes('permission') || errorMessage.includes('权限')) {
        this.permissionMessage = '录音功能需要麦克风权限，请在设置中授权后重试';
        this.isShowPermissionDialog = true;
      } else {
        this.showToast(`初始化录音器失败: ${errorMessage}`);
      }
    } finally {
      this.isInitializing = false;
    }
  }
  
  /**
   * 重新初始化录音器
   */
  private async retryInitialize(): Promise<void> {
    this.isShowPermissionDialog = false;
    await this.initializeRecorder();
  }

  /**
   * 开始录音
   */
  private async startRecording(): Promise<void> {
    try {
      await this.audioRecorderService.startRecording();
      this.startUpdateTimer();
      this.waveformData = [];
      hilog.info(DOMAIN, 'RecordPage', 'Recording started');
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to start recording: ${JSON.stringify(error)}`);
      this.showToast('开始录音失败');
    }
  }

  /**
   * 暂停录音
   */
  private async pauseRecording(): Promise<void> {
    try {
      await this.audioRecorderService.pauseRecording();
      this.stopUpdateTimer();
      hilog.info(DOMAIN, 'RecordPage', 'Recording paused');
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to pause recording: ${JSON.stringify(error)}`);
      this.showToast('暂停录音失败');
    }
  }

  /**
   * 恢复录音
   */
  private async resumeRecording(): Promise<void> {
    try {
      await this.audioRecorderService.resumeRecording();
      this.startUpdateTimer();
      hilog.info(DOMAIN, 'RecordPage', 'Recording resumed');
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to resume recording: ${JSON.stringify(error)}`);
      this.showToast('恢复录音失败');
    }
  }

  /**
   * 停止录音
   */
  private async stopRecording(): Promise<void> {
    try {
      const audioRecord = await this.audioRecorderService.stopRecording();
      this.stopUpdateTimer();
      
      if (audioRecord) {
        // 显示文件名输入对话框
        this.fileName = this.generateDefaultFileName();
        this.isShowFileNameDialog = true;
      }
      
      hilog.info(DOMAIN, 'RecordPage', 'Recording stopped');
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to stop recording: ${JSON.stringify(error)}`);
      this.showToast('停止录音失败');
    }
  }

  /**
   * 取消录音
   */
  private async cancelRecording(): Promise<void> {
    try {
      await this.audioRecorderService.cancelRecording();
      this.stopUpdateTimer();
      this.waveformData = [];
      this.recordDuration = 0;
      hilog.info(DOMAIN, 'RecordPage', 'Recording cancelled');
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to cancel recording: ${JSON.stringify(error)}`);
      this.showToast('取消录音失败');
    }
  }

  /**
   * 保存录音
   */
  private async saveRecording(): Promise<void> {
    try {
      if (!this.fileName.trim()) {
        this.showToast('请输入文件名');
        return;
      }

      const filePath = this.audioRecorderService.getCurrentFilePath();
      const duration = this.audioRecorderService.getCurrentDuration();
      
      if (filePath) {
        // 创建音频记录对象
        const audioRecord: AudioRecordInput = {
          fileName: this.fileName.trim(),
          filePath: filePath,
          duration: duration,
          fileSize: 0, // 将在数据库插入时计算
          createTime: Date.now(),
          isTop: false,
          groupId: 1 // 默认分组
        } as AudioRecordInput;
        
        // 保存到数据库
        await this.databaseService.insertAudioRecord(audioRecord);
        
        this.showToast('录音保存成功');
        this.isShowFileNameDialog = false;
        
        // 返回主页面
        setTimeout(() => {
          this.navigateBack();
        }, 1000);
      }
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `Failed to save recording: ${JSON.stringify(error)}`);
      this.showToast('保存录音失败');
    }
  }

  /**
   * 生成默认文件名
   */
  private generateDefaultFileName(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = (now.getMonth() + 1).toString().padStart(2, '0');
    const day = now.getDate().toString().padStart(2, '0');
    const hour = now.getHours().toString().padStart(2, '0');
    const minute = now.getMinutes().toString().padStart(2, '0');
    const second = now.getSeconds().toString().padStart(2, '0');
    
    return `录音_${year}${month}${day}_${hour}${minute}${second}`;
  }

  /**
   * 更新波形数据
   */
  private updateWaveform(amplitude: number): void {
    // 将振幅值添加到波形数据中
    this.waveformData.push(amplitude);
    
    // 限制波形数据长度，保持最近的120个数据点（更多数据点使波形更平滑）
    if (this.waveformData.length > 120) {
      this.waveformData.shift();
    }
    
    // 动态调整最大振幅，使波形显示更自然
    const currentMaxInData = Math.max(...this.waveformData);
    if (currentMaxInData > this.maxAmplitude) {
      this.maxAmplitude = currentMaxInData;
    } else if (currentMaxInData < this.maxAmplitude * 0.8) {
      // 如果当前最大值明显小于历史最大值，逐渐降低最大值
      this.maxAmplitude = Math.max(currentMaxInData * 1.2, 20); // 保持最小高度
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
   * 格式化时长显示
   */
  private formatDuration(duration: number): string {
    const totalSeconds = Math.floor(duration / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    const milliseconds = Math.floor((duration % 1000) / 10);
    
    return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}.${milliseconds.toString().padStart(2, '0')}`;
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

  /**
   * 获取录音按钮文本
   */
  private getRecordButtonText(): string {
    switch (this.recordState) {
      case RecordState.IDLE:
        return '开始录音';
      case RecordState.RECORDING:
        return '暂停';
      case RecordState.PAUSED:
        return '继续';
      case RecordState.STOPPED:
        return '重新录音';
      default:
        return '录音';
    }
  }

  /**
   * 获取录音按钮颜色
   */
  private getRecordButtonColor(): string {
    switch (this.recordState) {
      case RecordState.RECORDING:
        return '#FF3B30';
      case RecordState.PAUSED:
        return '#FF9500';
      default:
        return '#007AFF';
    }
  }

  /**
   * 获取波形条颜色
   */
  private getWaveformBarColor(amplitude: number, index: number): string {
    if (this.recordState !== RecordState.RECORDING) {
      return '#D0D0D0';
    }
    
    // 根据振幅强度设置颜色渐变
    const intensity = amplitude / this.maxAmplitude;
    
    if (intensity > 0.8) {
      return '#FF3B30'; // 高振幅：红色
    } else if (intensity > 0.6) {
      return '#FF9500'; // 中高振幅：橙色
    } else if (intensity > 0.3) {
      return '#007AFF'; // 中振幅：蓝色
    } else {
      return '#34C759'; // 低振幅：绿色
    }
  }

  build() {
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
        
        Text('录音')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        // 占位，保持标题居中
        Row()
          .width(40)
          .height(40)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 录音时长显示
      Column() {
        Text(this.formatDuration(this.recordDuration))
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ top: 40, bottom: 20 })
        
        Text(this.recordState === RecordState.RECORDING ? '正在录音...' : 
             this.recordState === RecordState.PAUSED ? '录音已暂停' : 
             this.recordState === RecordState.STOPPED ? '录音已完成' : '准备录音')
          .fontSize(16)
          .fontColor('#666666')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // 波形显示区域
      Column() {
        Text('音频波形')
          .fontSize(14)
          .fontColor('#999999')
          .margin({ bottom: 16 })
        
        // 波形容器
        Row() {
          ForEach(this.waveformData, (amplitude: number, index: number) => {
            Column()
              .width(2)
              .height(Math.max(4, (amplitude / this.maxAmplitude) * 80))
              .backgroundColor(this.getWaveformBarColor(amplitude, index))
              .borderRadius(1)
              .margin({ left: 0.5, right: 0.5 })
              .animation({
                duration: 100,
                curve: Curve.EaseOut
              })
          })
        }
        .width('100%')
        .height(100)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Bottom)
        .backgroundColor('#F0F0F0')
        .borderRadius(12)
        .padding({ left: 12, right: 12, top: 20, bottom: 20 })
        .border({ width: 1, color: '#E0E0E0' })
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 40, bottom: 40 })
      .layoutWeight(1)

      // 控制按钮区域
      Row() {
        // 取消按钮
        if (this.recordState !== RecordState.IDLE) {
          Button('取消')
            .fontSize(16)
            .fontColor('#FF3B30')
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#FF3B30' })
            .borderRadius(25)
            .width(80)
            .height(50)
            .onClick(() => this.cancelRecording())
        }
        
        Blank()
        
        // 主录音按钮
        Button() {
          Column() {
            if (this.isInitializing) {
              LoadingProgress()
                .width(40)
                .height(40)
                .color(Color.White)
            } else if (this.recordState === RecordState.RECORDING) {
              // 录音中显示暂停图标
              Row()
                .width(20)
                .height(20)
                .backgroundColor('#FFFFFF')
                .borderRadius(2)
            } else {
              // 其他状态显示录音图标
              Circle()
                .width(24)
                .height(24)
                .fill('#FFFFFF')
            }
          }
        }
        .width(80)
        .height(80)
        .backgroundColor(this.getRecordButtonColor())
        .borderRadius(40)
        .enabled(!this.isInitializing)
        .onClick(() => {
          if (this.isInitializing) {
            this.showToast('正在初始化录音器，请稍候...');
            return;
          }
          
          switch (this.recordState) {
            case RecordState.IDLE:
            case RecordState.STOPPED:
              this.startRecording();
              break;
            case RecordState.RECORDING:
              this.pauseRecording();
              break;
            case RecordState.PAUSED:
              this.resumeRecording();
              break;
          }
        })
        
        Blank()
        
        // 停止按钮
        if (this.recordState === RecordState.RECORDING || this.recordState === RecordState.PAUSED) {
          Button('完成')
            .fontSize(16)
            .fontColor('#007AFF')
            .backgroundColor('#FFFFFF')
            .border({ width: 1, color: '#007AFF' })
            .borderRadius(25)
            .width(80)
            .height(50)
            .onClick(() => this.stopRecording())
        }
      }
      .width('100%')
      .padding({ left: 40, right: 40, bottom: 40 })
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
    .bindContentCover(this.isShowFileNameDialog, this.FileNameDialog(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onAppear: () => {
        hilog.info(DOMAIN, 'RecordPage', 'File name dialog appeared');
      }
    })
    .bindContentCover(this.isShowPermissionDialog, this.PermissionDialog(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onAppear: () => {
        hilog.info(DOMAIN, 'RecordPage', 'Permission dialog appeared');
      }
    })
  }

  // 文件名输入对话框
  @Builder
  FileNameDialog() {
    Column() {
      Text('保存录音')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })

      TextInput({ placeholder: '请输入文件名', text: this.fileName })
        .width('100%')
        .height(40)
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.fileName = value;
        })

      Row() {
        Button('取消')
          .width('45%')
          .height(40)
          .backgroundColor('#E0E0E0')
          .fontColor('#333333')
          .onClick(() => {
            this.isShowFileNameDialog = false;
            this.fileName = '';
          })

        Button('保存')
          .width('45%')
          .height(40)
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .onClick(async () => {
            if (this.fileName.trim()) {
              await this.saveRecording();
            } else {
              this.showToast('请输入文件名');
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('80%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 10, color: '#00000020' })
  }
  
  @Builder
  PermissionDialog() {
    Column() {
      Text('权限请求')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ bottom: 20 })
        .fontColor('#333333')

      Text(this.permissionMessage)
        .fontSize(16)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 30 })
        .lineHeight(24)

      Row() {
        Button('取消')
          .width('45%')
          .height(40)
          .backgroundColor('#E0E0E0')
          .fontColor('#333333')
          .onClick(() => {
            this.isShowPermissionDialog = false;
            router.back();
          })

        Button('重试')
          .width('45%')
          .height(40)
          .backgroundColor('#007AFF')
          .fontColor(Color.White)
          .onClick(async () => {
            await this.retryInitialize();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('80%')
    .padding(20)
    .backgroundColor(Color.White)
    .borderRadius(10)
    .shadow({ radius: 10, color: '#00000020' })
  }
}

// 自定义对话框组件
@CustomDialog
struct FileNameDialogComponent {
  @State fileName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: (fileName: string) => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('保存录音')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 20 })
      
      TextInput({ placeholder: '请输入文件名', text: this.fileName })
        .width('100%')
        .height(40)
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
          .width(80)
          .height(40)
          .onClick(() => {
            this.controller.close();
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
          .width(80)
          .height(40)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm(this.fileName);
            }
            this.controller.close();
          })
      }
      .width('100%')
    }
    .width(280)
    .padding(20)
    .backgroundColor('#FFFFFF')
    .borderRadius(12)
  }
}