import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';
import { RecordState, AudioConfig, RecorderAudioConfig, RecordResult } from '../model/DataModel';
import { common } from '@kit.AbilityKit';
import { abilityAccessCtrl, bundleManager, Permissions } from '@kit.AbilityKit';
import { DevConfig, DevUtils } from '../config/DevConfig';

const TAG = 'AudioRecorderService';
const DOMAIN = 0x0000;

/**
 * 模拟录音器接口
 */
interface MockRecorder {
  prepare(config: media.AVRecorderConfig): Promise<void>;
  start(): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  stop(): Promise<void>;
  release(): Promise<void>;
  on(event: string, callback: (data?: Object) => void): void;
}

/**
 * 模拟录音器实现类
 */
class MockRecorderImpl implements MockRecorder {
  private service: AudioRecorderService;

  constructor(service: AudioRecorderService) {
    this.service = service;
  }

  async prepare(config: media.AVRecorderConfig): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：准备录音');
    await DevUtils.mockDelay(100);
    this.service.setMockRecorderState("prepared");
    this.service.handleMockStateChange("prepared" as media.AVRecorderState);
  }

  async start(): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：开始录音');
    await DevUtils.mockDelay(50);
    this.service.setMockRecorderState("started");
    this.service.handleMockStateChange("started" as media.AVRecorderState);
  }

  async pause(): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：暂停录音');
    await DevUtils.mockDelay(50);
    this.service.setMockRecorderState("paused");
    this.service.handleMockStateChange("paused" as media.AVRecorderState);
  }

  async resume(): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：恢复录音');
    await DevUtils.mockDelay(50);
    this.service.setMockRecorderState("started");
    this.service.handleMockStateChange("started" as media.AVRecorderState);
  }

  async stop(): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：停止录音');
    await DevUtils.mockDelay(100);
    this.service.setMockRecorderState("stopped");
    this.service.handleMockStateChange("stopped" as media.AVRecorderState);
    // 在开发模式下创建模拟音频文件
    await this.service.createMockAudioFile();
  }

  async release(): Promise<void> {
    DevUtils.devLog(TAG, '模拟录音器：释放资源');
    await DevUtils.mockDelay(50);
    this.service.setMockRecorderState("idle");
    this.service.setIsMockRecorder(false);
  }

  on(event: string, callback: (data?: Object) => void): void {
    // 模拟事件监听器，实际不需要做任何事情
    DevUtils.devLog(TAG, `模拟录音器：注册事件监听器 ${event}`);
  }
}

/**
 * 音频录制服务类
 * 负责音频录制功能的管理
 */
export class AudioRecorderService {
  private static instance: AudioRecorderService;
  private audioRecorder: media.AVRecorder | MockRecorder | null = null;
  private recordState: RecordState = RecordState.IDLE;
  private recordStartTime: number = 0;
  private recordDuration: number = 0;
  private currentFilePath: string = '';
  private context: common.UIAbilityContext | null = null;
  
  // 录制状态监听器
  private stateChangeListeners: Array<(state: RecordState) => void> = [];
  private durationUpdateListeners: Array<(duration: number) => void> = [];
  private amplitudeListeners: ((amplitude: number) => void)[] = [];
  private errorListeners: ((error: BusinessError) => void)[] = [];
  
  // 振幅检测相关
  private amplitudeTimer: number | null = null;
  private lastAmplitudeTime: number = 0;
  
  // 时长计时器相关
  private durationTimer: number | null = null;
  
  // 开发模式相关
  private isMockRecorder: boolean = false;
  private mockRecorderState: string = "idle";

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): AudioRecorderService {
    if (!AudioRecorderService.instance) {
      AudioRecorderService.instance = new AudioRecorderService();
    }
    return AudioRecorderService.instance;
  }

  /**
   * 初始化录音服务
   * @param context 应用上下文
   */
  async initialize(context: common.UIAbilityContext): Promise<void> {
    this.context = context;
    const maxRetries = 5; // 增加重试次数
    let lastError: Error | null = null;

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        hilog.info(DOMAIN, TAG, `Initializing AudioRecorderService (attempt ${attempt}/${maxRetries})`);

        // 显示当前运行模式
        if (DevConfig.isDevMode()) {
          DevUtils.devWarning(TAG, '🔧 当前运行在开发模式下，录音功能将使用模拟数据');
          DevUtils.devLog(TAG, DevConfig.getDevModeInfo());
          hilog.warn(DOMAIN, TAG, 'Running in DEVELOPMENT mode - using mock recording functionality');
        } else {
          hilog.info(DOMAIN, TAG, 'Running in PRODUCTION mode - using real recording functionality');
        }

        // 重置状态
        this.recordState = RecordState.IDLE;
        
        // 检查权限（包含动态请求）
        await this.checkRecordPermissions();
        hilog.info(DOMAIN, TAG, 'Permissions checked successfully');

        // 创建录音器
        await this.createRecorder();
        hilog.info(DOMAIN, TAG, 'Recorder created successfully');
        
        // 验证录音器状态
        if (!this.audioRecorder) {
          throw new Error("Recorder creation failed - recorder is null");
        }

        hilog.info(DOMAIN, TAG, 'AudioRecorderService initialized successfully');
        return;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        hilog.error(DOMAIN, TAG, `Initialization attempt ${attempt} failed: ${lastError.message}`);

        // 完全清理状态
        await this.cleanup();
        
        // 如果是权限错误，不需要重试太多次
        if (lastError.message.includes("permission") || lastError.message.includes("权限")) {
          if (attempt >= 2) {
            hilog.error(DOMAIN, TAG, 'Permission error persists, stopping retries');
            break;
          }
        }

        // 如果不是最后一次尝试，等待后重试
        if (attempt < maxRetries) {
          const delay = Math.min(attempt * 500, 2000); // 递增延迟，最大2秒
          hilog.info(DOMAIN, TAG, `Waiting ${delay}ms before retry...`);
          await new Promise<void>(resolve => setTimeout(resolve, delay));
        }
      }
    }

    // 所有重试都失败了
    const errorMessage = `Failed to initialize AudioRecorderService after ${maxRetries} attempts. Last error: ${lastError?.message || 'Unknown error'}`;
    hilog.error(DOMAIN, TAG, errorMessage);
    throw new Error(errorMessage);
  }
  
  /**
   * 清理录音器资源和状态
   */
  private async cleanup(): Promise<void> {
    try {
      if (this.audioRecorder) {
        // 尝试停止录音
        if (this.recordState === RecordState.RECORDING || this.recordState === RecordState.PAUSED) {
          try {
            await this.audioRecorder.stop();
          } catch (stopError) {
            hilog.warn(DOMAIN, TAG, `Failed to stop recorder during cleanup: ${stopError}`);
          }
        }
        
        // 释放录音器
        try {
          await this.audioRecorder.release();
        } catch (releaseError) {
          hilog.warn(DOMAIN, TAG, `Failed to release recorder during cleanup: ${releaseError}`);
        }
        
        this.audioRecorder = null;
      }
      
      // 重置状态并通知
      this.recordState = RecordState.IDLE;
      this.notifyStateChange(this.recordState);
      this.recordStartTime = 0;
      this.recordDuration = 0;
      this.currentFilePath = "";
      
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error during cleanup: ${error}`);
    }
  }

  /**
   * 检查录音权限
   */
  private async checkRecordPermissions(): Promise<void> {
    // 开发模式下绕过权限检查
    if (DevConfig.isDevMode()) {
      DevUtils.devLog(TAG, '开发模式：绕过权限检查，直接返回权限已授予');
      hilog.info(DOMAIN, TAG, 'Dev mode: Bypassing permission check - permissions granted');
      return;
    }

    if (!this.context) {
      throw new Error("Context not initialized");
    }

    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId = bundleInfo.appInfo.accessTokenId;

      // 检查麦克风权限
      const microphonePermission: Permissions = "ohos.permission.MICROPHONE";
      let micResult = await atManager.checkAccessToken(tokenId, microphonePermission);
      
      if (micResult !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        hilog.warn(DOMAIN, TAG, 'Microphone permission not granted, requesting permission');
        // 请求麦克风权限
        try {
          await atManager.requestPermissionsFromUser(this.context, [microphonePermission]);
          // 重新检查权限
          micResult = await atManager.checkAccessToken(tokenId, microphonePermission);
          if (micResult !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
            throw new Error("用户拒绝了麦克风权限，无法进行录音");
          }
        } catch (requestError) {
          hilog.error(DOMAIN, TAG, `Failed to request microphone permission: ${JSON.stringify(requestError)}`);
          throw new Error("请求麦克风权限失败，请在设置中手动开启权限");
        }
      }

      // 检查音频写入权限
      const writeAudioPermission: Permissions = "ohos.permission.WRITE_AUDIO";
      let writeResult = await atManager.checkAccessToken(tokenId, writeAudioPermission);
      
      if (writeResult !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
        hilog.warn(DOMAIN, TAG, 'Write audio permission not granted, requesting permission');
        // 请求音频写入权限
        try {
          await atManager.requestPermissionsFromUser(this.context, [writeAudioPermission]);
          // 重新检查权限
          writeResult = await atManager.checkAccessToken(tokenId, writeAudioPermission);
          if (writeResult !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
            throw new Error("用户拒绝了音频写入权限，无法保存录音文件");
          }
        } catch (requestError) {
          hilog.error(DOMAIN, TAG, `Failed to request write audio permission: ${JSON.stringify(requestError)}`);
          throw new Error("请求音频写入权限失败，请在设置中手动开启权限");
        }
      }

      hilog.info(DOMAIN, TAG, 'All recording permissions granted successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Permission check failed: ${JSON.stringify(error)}`);
      throw new Error(error instanceof Error ? error.message : String(error));
    }
  }

  /**
   * 创建录制器
   */
  private async createRecorder(): Promise<void> {
    try {
      // 如果已存在录音器，先释放
      if (this.audioRecorder) {
        hilog.info(DOMAIN, TAG, 'Releasing existing recorder before creating new one');
        try {
          if (DevConfig.isProdMode()) {
            await this.audioRecorder.release();
          }
        } catch (releaseError) {
          hilog.warn(DOMAIN, TAG, `Failed to release existing recorder: ${JSON.stringify(releaseError)}`);
        }
        this.audioRecorder = null;
      }
      
      // 开发模式下创建模拟录音器
      if (DevConfig.isDevMode()) {
        DevUtils.devLog(TAG, '开发模式：创建模拟录音器');
        hilog.info(DOMAIN, TAG, 'Dev mode: Creating mock recorder');
        this.audioRecorder = this.createMockRecorder();
        hilog.info(DOMAIN, TAG, 'Mock recorder created successfully');
        return;
      }
      
      hilog.info(DOMAIN, TAG, 'Creating new AVRecorder instance...');
      this.audioRecorder = await media.createAVRecorder();
      
      if (!this.audioRecorder) {
        throw new Error("AVRecorder creation returned null");
      }
      
      hilog.info(DOMAIN, TAG, 'Setting up recorder callbacks...');
      this.setupRecorderCallbacks();
      
      hilog.info(DOMAIN, TAG, 'Recorder created and configured successfully');
    } catch (error) {
      let errorMessage = "Failed to create recorder: ";
      if (error instanceof Error) {
        errorMessage += error.message;
      } else {
        errorMessage += String(error);
      }
      hilog.error(DOMAIN, TAG, errorMessage);
      
      // 清理状态
      this.audioRecorder = null;
      this.recordState = RecordState.ERROR;
      
      throw new Error(errorMessage);
    }
  }

  /**
   * 创建模拟录音器
   */
  private createMockRecorder(): MockRecorder {
    this.isMockRecorder = true;
    this.mockRecorderState = 'idle';
    return new MockRecorderImpl(this);
  }
  
  /**
   * 设置模拟录音器状态
   */
  public setMockRecorderState(state: string): void {
    this.mockRecorderState = state;
  }
  
  /**
   * 设置是否为模拟录音器
   */
  public setIsMockRecorder(isMock: boolean): void {
    this.isMockRecorder = isMock;
  }
  
  /**
   * 处理模拟录音器状态变化
   */
  public handleMockStateChange(state: media.AVRecorderState): void {
    this.handleStateChange(state);
  }
  
  /**
   * 创建模拟音频文件
   */
  public async createMockAudioFile(): Promise<void> {
    if (!this.currentFilePath || DevConfig.isProdMode()) {
      return;
    }
    
    try {
      const mockConfig = DevConfig.getMockRecordingConfig();
      const fileSize = DevConfig.generateMockFileSize(this.recordDuration);
      
      // 创建模拟的音频文件内容
      const mockContent = this.generateMockAudioContent(fileSize);
      
      // 确保目录存在
      const dirPath = this.currentFilePath.substring(0, this.currentFilePath.lastIndexOf("/"));
      if (!await fileIo.access(dirPath)) {
        await fileIo.mkdir(dirPath, true);
      }
      
      // 写入模拟音频文件
      const file = fileIo.openSync(this.currentFilePath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
      fileIo.writeSync(file.fd, mockContent);
      fileIo.closeSync(file);
      
      DevUtils.devLog(TAG, `模拟音频文件已创建：${this.currentFilePath}，大小：${fileSize}字节`);
      hilog.info(DOMAIN, TAG, `Mock audio file created: ${this.currentFilePath}, size: ${fileSize} bytes`);
    } catch (error) {
      DevUtils.devError(TAG, `创建模拟音频文件失败：${JSON.stringify(error)}`);
      hilog.error(DOMAIN, TAG, `Failed to create mock audio file: ${JSON.stringify(error)}`);
    }
  }
  
  /**
   * 生成模拟音频文件内容
   */
  private generateMockAudioContent(targetSize: number): string {
    const mockConfig = DevConfig.getMockRecordingConfig();
    const baseContent = mockConfig.mockAudioContent;
    
    // 根据目标大小生成内容
    let content = `# Mock Audio File - Generated in Dev Mode\n`;
    content += `# Duration: ${this.recordDuration}ms\n`;
    content += `# Target Size: ${targetSize} bytes\n`;
    content += `# Created: ${new Date().toISOString()}\n`;
    content += `# Base64 Audio Header: ${baseContent}\n`;
    
    // 填充内容到目标大小
    const padding = "A".repeat(Math.max(0, targetSize - content.length));
    content += padding;
    
    return content;
  }

  /**
   * 设置录制器回调
   */
  private setupRecorderCallbacks(): void {
    if (!this.audioRecorder || this.isMockRecorder) return;

    // 错误回调 - 使用正确的回调签名
    this.audioRecorder.on("error", (data?: Object) => {
      const error = data as BusinessError;
      hilog.error(DOMAIN, TAG, `Recorder error: ${JSON.stringify(error)}`);
      this.notifyError(error);
    });
  }

  /**
   * 处理状态变化
   */
  private handleStateChange(state: media.AVRecorderState): void {
    switch (state) {
      case "idle":
        this.recordState = RecordState.IDLE;
        break;
      case "prepared":
        this.recordState = RecordState.PREPARED;
        break;
      case "started":
        this.recordState = RecordState.RECORDING;
        this.startDurationTimer();
        this.startAmplitudeDetection();
        break;
      case "paused":
        this.recordState = RecordState.PAUSED;
        this.stopDurationTimer();
        this.stopAmplitudeDetection();
        break;
      case "stopped":
        this.recordState = RecordState.STOPPED;
        this.stopDurationTimer();
        this.stopAmplitudeDetection();
        break;
      case "error":
        this.recordState = RecordState.ERROR;
        this.stopDurationTimer();
        this.stopAmplitudeDetection();
        break;
      default:
        break;
    }
    this.notifyStateChange(this.recordState);
  }

  /**
   * 开始录制
   */
  public async startRecording(): Promise<void> {
    const currentState = this.recordState;
    hilog.info(DOMAIN, TAG, `Starting recording, current state: ${currentState}`);
    
    // 检查录音器是否已初始化
    if (!this.audioRecorder) {
      const errorMessage = "Recorder not initialized. Please call initialize() first.";
      hilog.error(DOMAIN, TAG, errorMessage);
      this.recordState = RecordState.ERROR;
      throw new Error(errorMessage);
    }

    // 检查当前状态
    if (this.recordState !== RecordState.IDLE) {
      const expectedState = RecordState.IDLE;
      const currentState = this.recordState;
      const errorMessage = `Cannot start recording in current state: ${currentState}. Expected state: ${expectedState}`;
      hilog.error(DOMAIN, TAG, errorMessage);
      throw new Error(errorMessage);
    }

    try {
      // 显示录音开始提示
      if (DevConfig.isDevMode()) {
        DevUtils.devLog(TAG, '🎤 开始模拟录音...');
      }

      hilog.info(DOMAIN, TAG, 'Preparing recorder configuration...');
      const config = await this.getRecordConfig();
      hilog.info(DOMAIN, TAG, `Record config: ${JSON.stringify(config)}`);
      
      hilog.info(DOMAIN, TAG, 'Preparing recorder...');
      await this.audioRecorder.prepare(config);
      
      hilog.info(DOMAIN, TAG, 'Starting recorder...');
      await this.audioRecorder.start();
      
      hilog.info(DOMAIN, TAG, 'Recording started successfully');
    } catch (error) {
      const errorMessage = `Failed to start recording: ${error instanceof Error ? error.message : String(error)}`;
      hilog.error(DOMAIN, TAG, errorMessage);
      
      // 设置错误状态
      this.recordState = RecordState.ERROR;
      this.notifyStateChange(this.recordState);
      
      // 尝试重置录音器状态（使用释放和重新创建的方式替代reset）
      try {
        if (this.audioRecorder) {
          await this.audioRecorder.release();
          this.audioRecorder = null;
          await this.createRecorder();
          hilog.info(DOMAIN, TAG, 'Recorder recreated after start failure');
        }
      } catch (recreateError) {
        hilog.warn(DOMAIN, TAG, `Failed to recreate recorder: ${JSON.stringify(recreateError)}`);
      }
      
      throw new Error(errorMessage);
    }
  }

  /**
   * 暂停录制
   */
  public async pauseRecording(): Promise<void> {
    if (!this.audioRecorder) {
      throw new Error("Recorder not initialized");
    }

    try {
      await this.audioRecorder.pause();
      hilog.info(DOMAIN, TAG, 'Recording paused');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to pause recording: ${JSON.stringify(error)}`);
      throw new Error(`Failed to pause recording: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 恢复录制
   */
  public async resumeRecording(): Promise<void> {
    if (!this.audioRecorder) {
      throw new Error("Recorder not initialized");
    }

    try {
      await this.audioRecorder.resume();
      hilog.info(DOMAIN, TAG, 'Recording resumed');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to resume recording: ${JSON.stringify(error)}`);
      throw new Error(`Failed to resume recording: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 停止录制
   */
  public async stopRecording(): Promise<RecordResult> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] ========== stopRecording() started ==========`);
    
    if (!this.audioRecorder) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] audioRecorder not initialized`);
      throw new Error("Recorder not initialized");
    }

    const currentState = this.recordState;
    hilog.info(DOMAIN, TAG, `[${timestamp}] Current recording state: ${currentState}`);
    hilog.info(DOMAIN, TAG, `[${timestamp}] Current file path: ${this.currentFilePath}`);
    hilog.info(DOMAIN, TAG, `[${timestamp}] Current recording duration: ${this.recordDuration}ms`);

    // 🔥 关键修复：在重新创建录音器前先保存这些值到局部变量
    const savedFilePath = this.currentFilePath;
    const savedDuration = this.recordDuration;
    hilog.info(DOMAIN, TAG, `[${timestamp}] Saved key data - file path: '${savedFilePath}', duration: ${savedDuration}ms`);

    try {
      hilog.info(DOMAIN, TAG, `[${timestamp}] Calling audioRecorder.stop()`);
      await this.audioRecorder.stop();
      hilog.info(DOMAIN, TAG, `[${timestamp}] audioRecorder.stop() executed successfully`);
      
      // 验证保存的数据
      if (!savedFilePath) {
        hilog.error(DOMAIN, TAG, `[${timestamp}] Saved file path is empty: '${savedFilePath}'`);
        throw new Error("Saved file path is empty");
      }
      
      if (savedDuration <= 0) {
        hilog.warn(DOMAIN, TAG, `[${timestamp}] Saved recording duration is abnormal: ${savedDuration}ms`);
      }
      
      hilog.info(DOMAIN, TAG, `[${timestamp}] Calling getFileSize() to get file size`);
      const fileSize = await this.getFileSize(savedFilePath);
      hilog.info(DOMAIN, TAG, `[${timestamp}] File size: ${fileSize} bytes`);
      
      // 🔥 关键修复：在获取文件大小后再重新创建录音器
      hilog.info(DOMAIN, TAG, `[${timestamp}] Recreating recorder`);
      await this.createRecorder();
      hilog.info(DOMAIN, TAG, `[${timestamp}] Recorder recreated successfully`);
      
      // 🔥 关键修复：清空当前录音相关状态，为下次录音做准备
      this.currentFilePath = "";
      this.recordDuration = 0;
      this.recordStartTime = 0;
      hilog.info(DOMAIN, TAG, `[${timestamp}] Recording state cleared, ready for next recording`);
      
      // 先设置为STOPPED状态，让UI知道录音已停止
      this.recordState = RecordState.STOPPED;
      hilog.info(DOMAIN, TAG, `[${timestamp}] Setting recording state to STOPPED`);
      this.notifyStateChange(this.recordState);
      hilog.info(DOMAIN, TAG, `[${timestamp}] STOPPED state change notification sent`);
      
      // 稍后设置为IDLE状态
      setTimeout(() => {
        this.recordState = RecordState.IDLE;
        hilog.info(DOMAIN, TAG, `[${timestamp}] Setting recording state to IDLE`);
        this.notifyStateChange(this.recordState);
        hilog.info(DOMAIN, TAG, `[${timestamp}] IDLE state change notification sent`);
      }, 100);
      
      hilog.info(DOMAIN, TAG, `[${timestamp}] Recording stop completed - file: ${savedFilePath}, duration: ${savedDuration}ms, size: ${fileSize} bytes`);
      
      const result: RecordResult = {
        filePath: savedFilePath,
        duration: savedDuration,
        fileSize
      };
      hilog.info(DOMAIN, TAG, `[${timestamp}] Return result details:`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] - filePath: '${result.filePath}'`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] - duration: ${result.duration}ms`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] - fileSize: ${result.fileSize} bytes`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] - Result object type: ${typeof result}`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] - Result is truthy: ${!!result}`);
      hilog.info(DOMAIN, TAG, `[${timestamp}] ========== stopRecording() completed, returning valid result ==========`);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] stopRecording() execution failed: ${JSON.stringify(error)}`);
      hilog.error(DOMAIN, TAG, `[${timestamp}] Error stack: ${error instanceof Error ? error.stack : 'No stack trace'}`);
      
      // 尝试重新创建录音器
      try {
        hilog.info(DOMAIN, TAG, `[${timestamp}] Attempting to recreate recorder`);
        await this.createRecorder();
        this.recordState = RecordState.IDLE;
        this.notifyStateChange(this.recordState);
        hilog.info(DOMAIN, TAG, `[${timestamp}] Recorder recreated successfully`);
      } catch (createError) {
        hilog.error(DOMAIN, TAG, `[${timestamp}] Failed to recreate recorder: ${JSON.stringify(createError)}`);
      }
      throw new Error(`Failed to stop recording: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 取消录制
   */
  public async cancelRecording(): Promise<void> {
    if (!this.audioRecorder) {
      throw new Error("Recorder not initialized");
    }

    try {
      await this.audioRecorder.stop();
      
      // 删除录制文件
      if (this.currentFilePath && await fileIo.access(this.currentFilePath)) {
        await fileIo.unlink(this.currentFilePath);
        hilog.info(DOMAIN, TAG, `Deleted cancelled recording file: ${this.currentFilePath}`);
      }
      
      // 重新创建录音器以便下次使用
      await this.createRecorder();
      this.recordState = RecordState.IDLE;
      this.notifyStateChange(this.recordState);
      
      this.currentFilePath = "";
      this.recordDuration = 0;
      
      hilog.info(DOMAIN, TAG, 'Recording cancelled');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to cancel recording: ${JSON.stringify(error)}`);
      // 尝试重新创建录音器
      try {
        await this.createRecorder();
        this.recordState = RecordState.IDLE;
        this.notifyStateChange(this.recordState);
      } catch (createError) {
        hilog.error(DOMAIN, TAG, `Failed to recreate recorder after cancel error: ${JSON.stringify(createError)}`);
      }
      throw new Error(`Failed to cancel recording: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取录制配置
   */
  private async getRecordConfig(): Promise<media.AVRecorderConfig> {
    const filePath = await this.generateFilePath();
    this.currentFilePath = filePath;
    this.recordStartTime = Date.now();
    this.recordDuration = 0;
    
    hilog.info(DOMAIN, TAG, `Generated file path: ${filePath}`);
    
    const config = {
      audioSourceType: media.AudioSourceType.AUDIO_SOURCE_TYPE_MIC,
      audioEncoder: media.CodecMimeType.AUDIO_AAC,
      audioEncodeBitRate: 128000,
      audioSampleRate: 44100,
      numberOfChannels: 2,
      format: media.ContainerFormatType.CFT_MPEG_4A,
      url: `file://${filePath}`,
      profile: {
        audioBitrate: 128000,
        audioChannels: 2,
        audioCodec: media.CodecMimeType.AUDIO_AAC,
        audioSampleRate: 44100,
        fileFormat: media.ContainerFormatType.CFT_MPEG_4A
      }
    } as media.AVRecorderConfig;
    
    hilog.info(DOMAIN, TAG, `Record config created: ${JSON.stringify(config)}`);
    return config;
  }

  /**
   * 生成文件路径
   */
  private async generateFilePath(fileName?: string): Promise<string> {
    if (!this.context) {
      throw new Error("Context not initialized");
    }

    const timestamp = Date.now();
    const name = fileName || `audio_${timestamp}`;
    const filesDir = this.context.filesDir;
    const audioDir = `${filesDir}/audio`;
    
    // 确保音频目录存在
    if (!await fileIo.access(audioDir)) {
      await fileIo.mkdir(audioDir);
    }
    
    return `${audioDir}/${name}.m4a`;
  }

  /**
   * 获取文件大小
   */
  private async getFileSize(filePath: string): Promise<number> {
    try {
      if (await fileIo.access(filePath)) {
        const stat = await fileIo.stat(filePath);
        return stat.size;
      }
      return 0;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get file size: ${JSON.stringify(error)}`);
      return 0;
    }
  }

  /**
   * 开始时长计时器
   */
  private startDurationTimer(): void {
    this.stopDurationTimer(); // 确保没有重复的计时器
    
    this.durationTimer = setInterval(() => {
      if (this.recordState === RecordState.RECORDING) {
        this.recordDuration = Date.now() - this.recordStartTime;
        this.notifyDurationUpdate(this.recordDuration);
      } else {
        this.stopDurationTimer();
      }
    }, 100); // 每100ms更新一次
  }

  /**
   * 停止时长计时器
   */
  private stopDurationTimer(): void {
    if (this.durationTimer !== null) {
      clearInterval(this.durationTimer);
      this.durationTimer = null;
    }
  }

  /**
   * 开始振幅检测
   */
  private startAmplitudeDetection(): void {
    this.stopAmplitudeDetection(); // 确保没有重复的检测器
    
    this.amplitudeTimer = setInterval(() => {
      if (this.recordState === RecordState.RECORDING) {
        const currentTime = Date.now();
        const timeDiff = currentTime - this.lastAmplitudeTime;
        
        // 生成振幅数据
        let amplitude = 0;
        if (timeDiff > 50) { // 每50ms更新一次
          if (DevConfig.isDevMode()) {
            // 开发模式：使用配置的模拟振幅数据
            amplitude = DevConfig.generateMockAmplitude();
            DevUtils.devLog(TAG, `模拟振幅：${amplitude.toFixed(2)}`);
          } else {
            // 生产模式：基于时间生成变化的振幅值，模拟真实录音
            const baseAmplitude = 20 + Math.sin(currentTime / 1000) * 15;
            const randomVariation = (Math.random() - 0.5) * 30;
            amplitude = Math.max(0, Math.min(100, baseAmplitude + randomVariation));
          }
          
          this.lastAmplitudeTime = currentTime;
          this.notifyAmplitudeUpdate(amplitude);
        }
      } else {
        this.stopAmplitudeDetection();
      }
    }, DevConfig.isDevMode() ? DevConfig.getMockRecordingConfig().amplitudeUpdateFrequency : 50); // 根据模式调整更新频率
  }

  /**
   * 停止振幅检测
   */
  private stopAmplitudeDetection(): void {
    if (this.amplitudeTimer !== null) {
      clearInterval(this.amplitudeTimer);
      this.amplitudeTimer = null;
    }
  }

  // ==================== 监听器管理 ====================

  /**
   * 设置状态变化回调（向后兼容方法）
   */
  public setStateChangeCallback(callback: (state: RecordState) => void): void {
    this.addStateChangeListener(callback);
  }

  /**
   * 设置时长更新回调（向后兼容方法）
   */
  public setDurationCallback(callback: (duration: number) => void): void {
    this.addDurationUpdateListener(callback);
  }

  /**
   * 设置振幅回调（向后兼容方法）
   */
  public setAmplitudeCallback(callback: (amplitude: number) => void): void {
    this.addAmplitudeListener(callback);
  }

  /**
   * 设置错误回调（向后兼容方法）
   */
  public setErrorCallback(callback: (error: string) => void): void {
    this.addErrorListener((error: BusinessError) => {
      callback(error.message || "Unknown error");
    });
  }

  /**
   * 添加状态变化监听器
   */
  public addStateChangeListener(listener: (state: RecordState) => void): void {
    this.stateChangeListeners.push(listener);
  }

  /**
   * 移除状态变化监听器
   */
  public removeStateChangeListener(listener: (state: RecordState) => void): void {
    const index = this.stateChangeListeners.indexOf(listener);
    if (index > -1) {
      this.stateChangeListeners.splice(index, 1);
    }
  }

  /**
   * 添加时长更新监听器
   */
  public addDurationUpdateListener(listener: (duration: number) => void): void {
    this.durationUpdateListeners.push(listener);
  }

  /**
   * 移除时长更新监听器
   */
  public removeDurationUpdateListener(listener: (duration: number) => void): void {
    const index = this.durationUpdateListeners.indexOf(listener);
    if (index > -1) {
      this.durationUpdateListeners.splice(index, 1);
    }
  }

  /**
   * 添加振幅监听器
   */
  public addAmplitudeListener(listener: (amplitude: number) => void): void {
    this.amplitudeListeners.push(listener);
  }

  /**
   * 移除振幅监听器
   */
  public removeAmplitudeListener(listener: (amplitude: number) => void): void {
    const index = this.amplitudeListeners.indexOf(listener);
    if (index > -1) {
      this.amplitudeListeners.splice(index, 1);
    }
  }

  /**
   * 添加错误监听器
   */
  public addErrorListener(listener: (error: BusinessError) => void): void {
    this.errorListeners.push(listener);
  }

  /**
   * 移除错误监听器
   */
  public removeErrorListener(listener: (error: BusinessError) => void): void {
    const index = this.errorListeners.indexOf(listener);
    if (index > -1) {
      this.errorListeners.splice(index, 1);
    }
  }

  /**
   * 通知状态变化
   */
  private notifyStateChange(state: RecordState): void {
    this.stateChangeListeners.forEach(listener => {
      try {
        listener(state);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Error in state change listener: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 通知时长更新
   */
  private notifyDurationUpdate(duration: number): void {
    this.durationUpdateListeners.forEach(listener => {
      try {
        listener(duration);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Error in duration update listener: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 通知振幅更新
   */
  private notifyAmplitudeUpdate(amplitude: number): void {
    this.amplitudeListeners.forEach(listener => {
      try {
        listener(amplitude);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Error in amplitude listener: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 通知错误
   */
  private notifyError(error: BusinessError): void {
    this.errorListeners.forEach(listener => {
      try {
        listener(error);
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Error in error listener: ${JSON.stringify(error)}`);
      }
    });
  }

  // ==================== 获取器方法 ====================

  /**
   * 获取当前录制状态
   */
  public getRecordState(): RecordState {
    return this.recordState;
  }

  /**
   * 获取当前录制时长
   */
  public getCurrentDuration(): number {
    return this.recordDuration;
  }

  /**
   * 获取当前文件路径
   */
  public getCurrentFilePath(): string {
    return this.currentFilePath;
  }

  /**
   * 是否正在录制
   */
  public isRecording(): boolean {
    return this.recordState === RecordState.RECORDING;
  }

  /**
   * 是否已暂停
   */
  public isPaused(): boolean {
    return this.recordState === RecordState.PAUSED;
  }

  /**
   * 释放资源
   */
  public async release(): Promise<void> {
    try {
      if (this.audioRecorder) {
        await this.audioRecorder.release();
        this.audioRecorder = null;
      }
      
      // 停止所有计时器
      this.stopDurationTimer();
      this.stopAmplitudeDetection();
      
      // 清空监听器
      this.stateChangeListeners = [];
      this.durationUpdateListeners = [];
      this.amplitudeListeners = [];
      this.errorListeners = [];
      
      this.recordState = RecordState.IDLE;
      this.currentFilePath = "";
      this.recordDuration = 0;
      
      hilog.info(DOMAIN, TAG, 'AudioRecorderService released');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to release AudioRecorderService: ${JSON.stringify(error)}`);
      throw new Error(`Failed to release AudioRecorderService: ${JSON.stringify(error)}`);
    }
  }
}