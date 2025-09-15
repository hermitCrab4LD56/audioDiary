import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { RecordState, AudioRecord, RecordResult } from '../model/DataModel';
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
  
  // 🔥 新增：保存停止录音后的结果数据
  private savedRecordResult: RecordResult | null = null;
  
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
        const previousState = this.recordState;
        this.recordState = state;
        hilog.info(DOMAIN, 'RecordPage', `Record state changed from ${previousState} to: ${state}`);
        
        // 处理状态变化的特殊逻辑
        if (state === RecordState.STOPPED) {
          hilog.info(DOMAIN, 'RecordPage', 'Recording stopped via state change callback');
          // 停止计时器
          this.stopUpdateTimer();
          // 注意：不在这里显示对话框，因为savedRecordResult还没有设置
          // 对话框将在stopRecording方法中显示
        }
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
        this.permissionMessage = 'Recording requires microphone permission, please grant permission in settings';
        this.isShowPermissionDialog = true;
      } else {
        this.showToast(`Failed to initialize recorder: ${errorMessage}`);
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
      this.showToast('Failed to start recording');
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
      this.showToast('Failed to pause recording');
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
      this.showToast('Failed to resume recording');
    }
  }

  /**
   * 停止录音
   */
  private async stopRecording(): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ========== stopRecording() started ==========`);
    const currentState = this.recordState;
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Current recording state: ${currentState}`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Current recording duration: ${this.recordDuration}ms`);
    
    // 🔥 关键修复：立即更新状态为STOPPED，确保UI立即响应
    this.recordState = RecordState.STOPPED;
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ✅ Recording state immediately set to STOPPED`);
    
    try {
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Calling audioRecorderService.stopRecording()`);
      const audioRecord = await this.audioRecorderService.stopRecording();
      
      // 详细检查返回值
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecorderService.stopRecording() return type: ${typeof audioRecord}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecorderService.stopRecording() result: ${JSON.stringify(audioRecord)}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord is truthy: ${!!audioRecord}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord is null: ${audioRecord === null}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord is undefined: ${audioRecord === undefined}`);
      
      if (audioRecord) {
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord.filePath: ${audioRecord.filePath}`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord.duration: ${audioRecord.duration}`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord.fileSize: ${audioRecord.fileSize}`);
      }
      
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Calling stopUpdateTimer()`);
      this.stopUpdateTimer();
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] stopUpdateTimer() completed`);
      
      if (audioRecord) {
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecord exists, preparing to show filename dialog`);
        
        // 🔥 关键修复：保存RecordResult数据供saveRecording使用
        this.savedRecordResult = audioRecord;
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 💾 RecordResult data saved:`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - savedRecordResult.filePath: '${this.savedRecordResult.filePath}'`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - savedRecordResult.duration: ${this.savedRecordResult.duration}ms`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - savedRecordResult.fileSize: ${this.savedRecordResult.fileSize} bytes`);
        
        // 生成默认文件名
        this.fileName = this.generateDefaultFileName();
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Generated default filename: ${this.fileName}`);
        
        // 显示文件名输入对话框
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Setting isShowFileNameDialog from ${this.isShowFileNameDialog} to true`);
        this.isShowFileNameDialog = true;
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] isShowFileNameDialog current value: ${this.isShowFileNameDialog}`);
        
        // 强制UI更新
        setTimeout(() => {
          hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Delayed check - isShowFileNameDialog: ${this.isShowFileNameDialog}`);
        }, 100);
        
      } else {
        hilog.warn(DOMAIN, 'RecordPage', `[${timestamp}] ❌ audioRecord is null or undefined, cannot show dialog`);
        hilog.warn(DOMAIN, 'RecordPage', `[${timestamp}] This might be the reason for UI staying`);
        this.savedRecordResult = null;
        this.showToast('Failed to get recording data');
      }
      
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ========== stopRecording() completed ==========`);
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ stopRecording() failed: ${JSON.stringify(error)}`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] Error stack: ${error instanceof Error ? error.stack : 'No stack trace'}`);
      this.showToast('Failed to stop recording');
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
   * 自动保存录音（不显示对话框）- 已禁用，避免重复保存
   */
  private async autoSaveRecording(): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ⚠️ autoSaveRecording() called but disabled to prevent duplicate saves`);
    // 此方法已禁用，避免与用户手动保存重复
    // 录音数据已在stopRecording()中保存到savedRecordResult
    // 用户需要通过点击"完成"按钮来保存录音
  }

  /**
   * 保存录音
   */
  private async saveRecording(): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🎯 Starting recording save process`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Input filename: '${this.fileName}'`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] audioRecorderService status: ${this.audioRecorderService ? 'initialized' : 'not initialized'}`);
    
    if (!this.fileName.trim()) {
      hilog.warn(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 文件名为空，无法保存`);
      this.showToast('请输入文件名');
      return;
    }

    try {
      const timestamp = new Date().toISOString();
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🎯 开始保存录音，文件名: ${this.fileName}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📊 录音数据详情: 时长=${this.savedRecordResult?.duration}ms, 文件大小=${this.savedRecordResult?.fileSize}字节`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📂 文件路径: ${this.savedRecordResult?.filePath}`);
      
      // 🔥 关键修复：使用保存的RecordResult数据而不是重新获取
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🔍 检查保存的RecordResult数据`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] savedRecordResult是否存在: ${!!this.savedRecordResult}`);
      
      if (!this.savedRecordResult) {
        hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ savedRecordResult为空，无法保存`);
        this.showToast('录音数据丢失，请重新录音');
        return;
      }
      
      const filePath = this.savedRecordResult.filePath;
      const duration = this.savedRecordResult.duration;
      const fileSize = this.savedRecordResult.fileSize;
      
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📁 使用保存的文件路径: '${filePath}'`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ⏱️ 使用保存的录音时长: ${duration}ms`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📊 使用保存的文件大小: ${fileSize} bytes`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 文件路径类型: ${typeof filePath}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 文件路径是否为空: ${!filePath}`);
      
      // 验证关键数据
      if (!filePath) {
        hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 保存的文件路径为空，无法保存`);
        this.showToast('录音文件路径获取失败');
        return;
      }
      
      if (duration <= 0) {
        hilog.warn(DOMAIN, 'RecordPage', `[${timestamp}] ⚠️ 保存的录音时长异常: ${duration}ms`);
      }

      // 创建音频记录对象
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📝 创建音频记录对象`);
      const audioRecord: AudioRecordInput = {
        fileName: this.fileName.trim(),
        filePath: filePath,
        duration: duration,
        fileSize: fileSize, // 🔥 使用保存的实际文件大小
        createTime: Date.now(),
        isTop: false,
        groupId: 0 // 0表示未分组
      };
      
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 音频记录对象详情:`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 文件名: '${audioRecord.fileName}'`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 文件路径: '${audioRecord.filePath}'`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 时长: ${audioRecord.duration}ms`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 文件大小: ${audioRecord.fileSize}字节`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 创建时间: ${new Date(audioRecord.createTime).toLocaleString()}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}]   - 分组ID: ${audioRecord.groupId}`);

      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🔄 正在调用数据库保存方法...`);
      
      // 保存到数据库
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 💾 开始保存到数据库`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] databaseService status: ${this.databaseService ? 'initialized' : 'not initialized'}`);
      
      const result = await this.databaseService.insertAudioRecord(audioRecord);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 数据库保存结果: ${result}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 结果类型: ${typeof result}`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📊 数据库保存结果: ${result > 0 ? '成功' : '失败'}`);
      
      if (result > 0) {
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ✅ 录音保存成功，记录ID: ${result}`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ✅ 录音保存成功！准备跳转回主页面`);
        this.showToast('录音保存成功');
        
        // 🔥 清空保存的录音数据，为下次录音做准备
        this.savedRecordResult = null;
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🧹 已清空savedRecordResult`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🧹 已清空保存的录音数据`);
        
        // 关闭对话框
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🔒 关闭文件名对话框`);
        this.isShowFileNameDialog = false;
        this.fileName = '';
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 对话框状态已更新: isShowFileNameDialog=${this.isShowFileNameDialog}`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🚪 已关闭文件名对话框`);
        
        // 返回主页面
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🏠 准备跳转回主页面`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 调用 router.back() 前的状态检查完成`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ⏰ 准备在1000ms后跳转回主页面`);
        
        setTimeout(() => {
          hilog.info(DOMAIN, 'RecordPage', `[${new Date().toISOString()}] 🚀 开始跳转回主页面`);
          hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 执行页面返回`);
          this.navigateBack();
        }, 1000);
        
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ✅ 已设置延时跳转，页面跳转指令已发出`);
      } else {
        hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 数据库保存失败，返回值: ${result}`);
        hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 录音保存失败`);
        this.showToast('保存失败，请重试');
      }
    } catch (error) {
      const timestamp = new Date().toISOString();
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 保存录音时发生错误:`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] Error message: ${error instanceof Error ? error.message : String(error)}`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] 错误堆栈: ${error instanceof Error ? error.stack : 'No stack trace'}`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 保存录音时发生错误: ${JSON.stringify(error)}`);
      this.showToast('保存失败，请重试');
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
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🔄 navigateBack() 开始执行`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 当前页面状态检查:`);
    const currentState = this.recordState;
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - recordState: ${currentState}`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - isShowFileNameDialog: ${this.isShowFileNameDialog}`);
    hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] - fileName: '${this.fileName}'`);
    
    try {
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Preparing to call router.back()`);
      const routerStatus = 'available';
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] router object status: ${routerStatus}`);
      
      router.back();
      
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] router.back() called successfully`);
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Page navigation command issued, waiting for system processing`);
      
      // 添加延时检查，确认页面是否真的跳转了
      setTimeout(() => {
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Delayed check: page navigation status`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] If you see this log, the page may not have navigated successfully`);
      }, 2000);
      
    } catch (error) {
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] navigateBack() execution failed:`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] 错误信息: ${error instanceof Error ? error.message : String(error)}`);
      hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] 错误堆栈: ${error instanceof Error ? error.stack : 'No stack trace'}`);
      
      // 如果router.back()失败，尝试其他跳转方式
      hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Trying alternative navigation method`);
      try {
        router.replaceUrl({ url: 'pages/Index' });
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] Successfully navigated using router.replaceUrl()`);
      } catch (replaceError) {
        hilog.error(DOMAIN, 'RecordPage', `[${timestamp}] Alternative navigation method also failed: ${replaceError instanceof Error ? replaceError.message : String(replaceError)}`);
      }
    }
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
        
        Text(this.recordState === RecordState.RECORDING ? 'Recording...' : 
             this.recordState === RecordState.PAUSED ? 'Recording Paused' : 
             this.recordState === RecordState.STOPPED ? 'Recording Completed' : 'Ready to Record')
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
                .color('#FFFFFF')
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
            .onClick(() => {
              const timestamp = new Date().toISOString();
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🎯 ========== 完成按钮被点击 ==========`);
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📊 当前录音状态: ${this.recordState}`);
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ⏱️ 当前录音时长: ${this.recordDuration}ms (${this.formatDuration(this.recordDuration)})`);
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🔊 当前振幅: ${this.currentAmplitude}`);
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📈 波形数据点数: ${this.waveformData.length}`);
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 💾 已保存的录音结果: ${this.savedRecordResult ? '存在' : '不存在'}`);
              if (this.savedRecordResult) {
                hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📂 保存的文件路径: '${this.savedRecordResult.filePath}'`);
                hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ⏱️ 保存的时长: ${this.savedRecordResult.duration}ms`);
                hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 📊 保存的文件大小: ${this.savedRecordResult.fileSize} bytes`);
              }
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🚀 开始调用 stopRecording() 方法`);
              this.stopRecording();
            })
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
      backgroundColor: '#80000000',
      onAppear: () => {
        const timestamp = new Date().toISOString();
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ✅ 文件名对话框已显示`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] isShowFileNameDialog: ${this.isShowFileNameDialog}`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] fileName: ${this.fileName}`);
      },
      onDisappear: () => {
        const timestamp = new Date().toISOString();
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] ❌ 文件名对话框已隐藏`);
        hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] isShowFileNameDialog: ${this.isShowFileNameDialog}`);
      }
    })
    .bindContentCover(this.isShowPermissionDialog, this.PermissionDialog(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: '#80000000',
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
            const timestamp = new Date().toISOString();
            hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 🚫 用户点击取消按钮`);
            this.isShowFileNameDialog = false;
            this.fileName = '';
            hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 对话框已关闭，文件名已清空`);
          })

        Button('保存')
          .width('45%')
          .height(40)
          .backgroundColor('#007AFF')
          .fontColor('#FFFFFF')
          .onClick(async () => {
            const timestamp = new Date().toISOString();
            hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 💾 用户点击保存按钮`);
            hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 当前文件名: '${this.fileName}'`);
            hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 文件名trim后: '${this.fileName.trim()}'`);
            
            if (this.fileName.trim()) {
              hilog.info(DOMAIN, 'RecordPage', `[${timestamp}] 文件名有效，开始调用 saveRecording()`);
              await this.saveRecording();
            } else {
              hilog.warn(DOMAIN, 'RecordPage', `[${timestamp}] 文件名为空，显示提示信息`);
              this.showToast('请输入文件名');
            }
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('80%')
    .padding(20)
    .backgroundColor('#FFFFFF')
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
          .fontColor('#FFFFFF')
          .onClick(async () => {
            await this.retryInitialize();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('80%')
    .padding(20)
    .backgroundColor('#FFFFFF')
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