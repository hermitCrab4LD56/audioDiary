import { media } from '@kit.MediaKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PlayState, AudioConfig } from '../model/DataModel';
import { fileIo } from '@kit.CoreFileKit';
import { DevConfig, DevUtils } from '../config/DevConfig';

const DOMAIN = 0x0000;

/**
 * 模拟播放器接口
 */
interface MockPlayer {
  prepare(): Promise<void>;
  play(): Promise<void>;
  pause(): Promise<void>;
  resume(): Promise<void>;
  stop(): Promise<void>;
  release(): Promise<void>;
  seekTo(position: number): Promise<void>;
  setVolume(volume: number): Promise<void>;
  setPlaybackSpeed(speed: number): Promise<void>;
  on(event: string, callback: (data?: Object) => void): void;
}

/**
 * 模拟播放器实现类
 */
class MockPlayerImpl implements MockPlayer {
  private service: AudioPlayerService;
  private currentPosition: number = 0;
  private duration: number = 0;
  private isPlaying: boolean = false;
  private volume: number = 1.0;
  private playbackSpeed: number = 1.0;
  private positionTimer: number | null = null;

  constructor(service: AudioPlayerService) {
    this.service = service;
  }

  async prepare(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：准备播放');
    await DevUtils.mockDelay(100);
    this.duration = 30000; // 30秒模拟音频
    this.currentPosition = 0;
  }

  async play(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：开始播放');
    await DevUtils.mockDelay(50);
    this.isPlaying = true;
    this.startPositionTimer();
    this.service.handleMockStateChange(PlayState.PLAYING);
  }

  async pause(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：暂停播放');
    await DevUtils.mockDelay(50);
    this.isPlaying = false;
    this.stopPositionTimer();
    this.service.handleMockStateChange(PlayState.PAUSED);
  }

  async resume(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：恢复播放');
    await DevUtils.mockDelay(50);
    this.isPlaying = true;
    this.startPositionTimer();
    this.service.handleMockStateChange(PlayState.PLAYING);
  }

  async stop(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：停止播放');
    await DevUtils.mockDelay(50);
    this.isPlaying = false;
    this.currentPosition = 0;
    this.stopPositionTimer();
    this.service.handleMockStateChange(PlayState.STOPPED);
  }

  async release(): Promise<void> {
    DevUtils.devLog('MockPlayer', '模拟播放器：释放资源');
    this.stopPositionTimer();
  }

  async seekTo(position: number): Promise<void> {
    DevUtils.devLog('MockPlayer', `模拟播放器：跳转到位置 ${position}ms`);
    await DevUtils.mockDelay(50);
    this.currentPosition = Math.max(0, Math.min(position, this.duration));
    this.service.handleMockPositionUpdate(this.currentPosition);
  }

  async setVolume(volume: number): Promise<void> {
    DevUtils.devLog('MockPlayer', `模拟播放器：设置音量 ${volume}`);
    this.volume = volume;
  }

  async setPlaybackSpeed(speed: number): Promise<void> {
    DevUtils.devLog('MockPlayer', `模拟播放器：设置播放速度 ${speed}`);
    this.playbackSpeed = speed;
  }

  on(event: string, callback: (data?: Object) => void): void {
    DevUtils.devLog('MockPlayer', `模拟播放器：注册事件监听器 ${event}`);
  }

  private startPositionTimer(): void {
    this.stopPositionTimer();
    this.positionTimer = setInterval(() => {
      if (this.isPlaying) {
        this.currentPosition += 100; // 每100ms增加100ms位置
        if (this.currentPosition >= this.duration) {
          this.currentPosition = this.duration;
          this.isPlaying = false;
          this.stopPositionTimer();
          this.service.handleMockCompletion();
        } else {
          this.service.handleMockPositionUpdate(this.currentPosition);
        }
      }
    }, 100);
  }

  private stopPositionTimer(): void {
    if (this.positionTimer) {
      clearInterval(this.positionTimer);
      this.positionTimer = null;
    }
  }
}

/**
 * 音频播放服务类
 * 负责处理音频文件的播放、暂停、停止等功能
 */
export class AudioPlayerService {
  private static instance: AudioPlayerService;
  private audioPlayer: media.AVPlayer | null = null;
  private currentFilePath: string = '';
  private playState: PlayState = PlayState.STOPPED;
  private duration: number = 0;
  private currentPosition: number = 0;
  private stateChangeCallback?: (state: PlayState) => void;
  private progressCallback?: (position: number, duration: number) => void;
  private errorCallback?: (error: string) => void;
  private completionCallback?: () => void;
  private progressTimer: number | null = null;
  private isMockPlayer: boolean = false;
  private mockPlayer: MockPlayerImpl | null = null;

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): AudioPlayerService {
    if (!AudioPlayerService.instance) {
      AudioPlayerService.instance = new AudioPlayerService();
    }
    return AudioPlayerService.instance;
  }

  /**
   * 设置状态变化回调
   */
  public setStateChangeCallback(callback: (state: PlayState) => void): void {
    this.stateChangeCallback = callback;
  }

  /**
   * 设置播放进度回调
   */
  public setProgressCallback(callback: (position: number, duration: number) => void): void {
    this.progressCallback = callback;
  }

  /**
   * 设置错误回调
   */
  public setErrorCallback(callback: (error: string) => void): void {
    this.errorCallback = callback;
  }

  /**
   * 设置播放完成回调
   */
  public setCompletionCallback(callback: () => void): void {
    this.completionCallback = callback;
  }

  /**
   * 设置播放位置回调
   */
  public setPositionCallback(callback: (position: number) => void): void {
    this.progressCallback = (position: number, duration: number) => {
      callback(position);
    };
  }

  /**
   * 设置时长回调
   */
  public setDurationCallback(callback: (duration: number) => void): void {
    // 当时长更新时调用回调
    const originalCallback = this.progressCallback;
    this.progressCallback = (position: number, duration: number) => {
      callback(duration);
      if (originalCallback) {
        originalCallback(position, duration);
      }
    };
  }

  /**
   * 准备播放
   */
  public async prepare(filePath: string): Promise<void> {
    try {
      await this.initPlayer();
      
      if (!this.audioPlayer) {
        throw new Error('Failed to initialize player');
      }

      this.audioPlayer.url = `file://${filePath}`;
      this.currentFilePath = filePath;
      
      await this.audioPlayer.prepare();
      
      hilog.info(DOMAIN, 'AudioPlayerService', 'Audio prepared successfully');
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to prepare audio: ${JSON.stringify(error)}`);
      this.handleError(`Failed to prepare playback: ${JSON.stringify(error)}`);
      throw new Error(`Failed to prepare playback: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 设置播放速度
   */
  public async setPlaybackSpeed(speed: number): Promise<void> {
    try {
      if (this.audioPlayer && speed > 0 && speed <= 3.0) {
        // 注意：AVPlayer可能不支持播放速度设置，这里提供接口但可能无效果
        hilog.info(DOMAIN, 'AudioPlayerService', `Playback speed set to: ${speed}`);
        // 实际的速度设置需要根据具体的API文档实现
        // await this.audioPlayer.setSpeed(speed);
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to set playback speed: ${JSON.stringify(error)}`);
      throw new Error(`Failed to set playback speed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 初始化播放器
   */
  private async initPlayer(): Promise<void> {
    try {
      // 开发模式下创建模拟播放器
      if (DevConfig.isDevMode()) {
        DevUtils.devLog('AudioPlayerService', '开发模式：创建模拟播放器');
        hilog.info(DOMAIN, 'AudioPlayerService', 'Dev mode: Creating mock player');
        this.isMockPlayer = true;
        this.mockPlayer = new MockPlayerImpl(this);
        hilog.info(DOMAIN, 'AudioPlayerService', 'Mock player created successfully');
        return;
      }
      
      if (this.audioPlayer) {
        await this.releasePlayer();
      }

      this.audioPlayer = await media.createAVPlayer();
      
      // 设置状态变化监听
      this.audioPlayer.on('stateChange', (state: media.AVPlayerState) => {
        hilog.info(DOMAIN, 'AudioPlayerService', `Player state changed to: ${state}`);
        this.handleStateChange(state);
      });

      // 设置错误监听
      this.audioPlayer.on('error', (error: BusinessError<void>) => {
        hilog.error(DOMAIN, 'AudioPlayerService', `Player error: ${JSON.stringify(error)}`);
        this.handleError(`Playback error: ${error.message}`);
      });

      // 设置播放完成监听
      this.audioPlayer.on('endOfStream', () => {
        hilog.info(DOMAIN, 'AudioPlayerService', 'Playback completed');
        this.handleCompletion();
      });

      // 设置时长变化监听
      this.audioPlayer.on('durationUpdate', (duration: number) => {
        this.duration = duration;
        hilog.info(DOMAIN, 'AudioPlayerService', `Duration updated: ${duration}ms`);
      });

      // 设置播放位置变化监听
      this.audioPlayer.on('timeUpdate', (time: number) => {
        this.currentPosition = time;
        if (this.progressCallback) {
          this.progressCallback(time, this.duration);
        }
      });

    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to init player: ${JSON.stringify(error)}`);
      throw new Error(`Failed to initialize player: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 处理状态变化
   */
  private handleStateChange(state: media.AVPlayerState): void {
    switch (state) {
      case 'idle':
        this.playState = PlayState.STOPPED;
        break;
      case 'initialized':
      case 'prepared':
        this.playState = PlayState.PAUSED;
        break;
      case 'playing':
        this.playState = PlayState.PLAYING;
        this.startProgressTimer();
        break;
      case 'paused':
        this.playState = PlayState.PAUSED;
        this.stopProgressTimer();
        break;
      case 'stopped':
        this.playState = PlayState.STOPPED;
        this.stopProgressTimer();
        this.currentPosition = 0;
        break;
      case 'completed':
        this.playState = PlayState.STOPPED;
        this.stopProgressTimer();
        break;
      case 'error':
        this.playState = PlayState.STOPPED;
        this.stopProgressTimer();
        break;
    }

    if (this.stateChangeCallback) {
      this.stateChangeCallback(this.playState);
    }
  }

  /**
   * 处理错误
   */
  private handleError(error: string): void {
    this.playState = PlayState.STOPPED;
    this.stopProgressTimer();
    
    if (this.stateChangeCallback) {
      this.stateChangeCallback(this.playState);
    }
    
    if (this.errorCallback) {
      this.errorCallback(error);
    }
  }

  /**
   * 处理播放完成
   */
  private handleCompletion(): void {
    this.playState = PlayState.STOPPED;
    this.currentPosition = 0;
    this.stopProgressTimer();
    
    if (this.stateChangeCallback) {
      this.stateChangeCallback(this.playState);
    }
    
    if (this.completionCallback) {
      this.completionCallback();
    }
  }

  /**
   * 处理模拟播放器状态变化
   */
  public handleMockStateChange(state: PlayState): void {
    this.playState = state;
    if (this.stateChangeCallback) {
      this.stateChangeCallback(state);
    }
  }

  /**
   * 处理模拟播放器位置更新
   */
  public handleMockPositionUpdate(position: number): void {
    this.currentPosition = position;
    if (this.progressCallback) {
      this.progressCallback(position, this.duration);
    }
  }

  /**
   * 处理模拟播放器播放完成
   */
  public handleMockCompletion(): void {
    this.handleCompletion();
  }

  /**
   * 开始进度定时器
   */
  private startProgressTimer(): void {
    this.stopProgressTimer();
    this.progressTimer = setInterval(() => {
      if (this.audioPlayer && this.playState === PlayState.PLAYING) {
        // 通过timeUpdate事件获取当前位置，这里只是备用机制
        if (this.progressCallback) {
          this.progressCallback(this.currentPosition, this.duration);
        }
      }
    }, 100); // 每100ms更新一次
  }

  /**
   * 停止进度定时器
   */
  private stopProgressTimer(): void {
    if (this.progressTimer) {
      clearInterval(this.progressTimer);
      this.progressTimer = null;
    }
  }

  /**
   * 播放音频文件
   */
  public async play(filePath: string): Promise<void> {
    try {
      hilog.info(DOMAIN, 'AudioPlayerService', `Starting to play: ${filePath}`);
      
      // 开发模式下使用模拟播放器
      if (DevConfig.isDevMode()) {
        DevUtils.devLog('AudioPlayerService', `模拟播放：${filePath}`);
        await this.playWithMockPlayer(filePath);
        return;
      }
      
      // 检查文件是否存在
      if (!await fileIo.access(filePath)) {
        throw new Error('Audio file does not exist');
      }

      // 如果是同一个文件且处于暂停状态，直接恢复播放
      if (this.currentFilePath === filePath && this.playState === PlayState.PAUSED && this.audioPlayer) {
        await this.resume();
        return;
      }

      // 初始化播放器
      await this.initPlayer();
      
      if (!this.audioPlayer) {
        throw new Error('Failed to initialize player');
      }

      // 设置音频源
      this.audioPlayer.url = `file://${filePath}`;
      this.currentFilePath = filePath;
      
      // 准备播放
      await this.audioPlayer.prepare();
      
      // 开始播放
      await this.audioPlayer.play();
      
      hilog.info(DOMAIN, 'AudioPlayerService', 'Audio playback started successfully');
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to play audio: ${JSON.stringify(error)}`);
      this.handleError(`Playback failed: ${JSON.stringify(error)}`);
      throw new Error(`Playback failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 模拟播放器播放方法
   */
  private async playWithMockPlayer(filePath: string): Promise<void> {
    try {
      if (!this.mockPlayer) {
        await this.initPlayer();
      }
      
      if (!this.mockPlayer) {
        throw new Error('Failed to initialize mock player');
      }
      
      this.currentFilePath = filePath;
      this.duration = 30000; // 30秒模拟音频
      
      await this.mockPlayer.prepare();
      await this.mockPlayer.play();
      
      DevUtils.devLog('AudioPlayerService', '模拟播放开始');
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Mock playback failed: ${JSON.stringify(error)}`);
      this.handleError(`Mock playback failed: ${JSON.stringify(error)}`);
      throw new Error(`Mock playback failed: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 暂停播放
   */
  public async pause(): Promise<void> {
    try {
      if (this.isMockPlayer && this.mockPlayer) {
        await this.mockPlayer.pause();
        return;
      }
      
      if (this.audioPlayer && this.playState === PlayState.PLAYING) {
        await this.audioPlayer.pause();
        hilog.info(DOMAIN, 'AudioPlayerService', 'Audio playback paused');
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to pause audio: ${JSON.stringify(error)}`);
      this.handleError(`Pause failed: ${JSON.stringify(error)}`);
      throw new Error(`Pause failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 恢复播放
   */
  public async resume(): Promise<void> {
    try {
      if (this.isMockPlayer && this.mockPlayer) {
        await this.mockPlayer.resume();
        return;
      }
      
      if (this.audioPlayer && this.playState === PlayState.PAUSED) {
        await this.audioPlayer.play();
        hilog.info(DOMAIN, 'AudioPlayerService', 'Audio playback resumed');
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to resume audio: ${JSON.stringify(error)}`);
      this.handleError(`Resume playback failed: ${JSON.stringify(error)}`);
      throw new Error(`Resume playback failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 停止播放
   */
  public async stop(): Promise<void> {
    try {
      if (this.isMockPlayer && this.mockPlayer) {
        await this.mockPlayer.stop();
        return;
      }
      
      if (this.audioPlayer) {
        await this.audioPlayer.stop();
        hilog.info(DOMAIN, 'AudioPlayerService', 'Audio playback stopped');
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to stop audio: ${JSON.stringify(error)}`);
      this.handleError(`Stop playback failed: ${JSON.stringify(error)}`);
      throw new Error(`Stop playback failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 跳转到指定位置
   */
  public async seekTo(position: number): Promise<void> {
    try {
      if (this.audioPlayer && position >= 0 && position <= this.duration) {
        await this.audioPlayer.seek(position);
        this.currentPosition = position;
        hilog.info(DOMAIN, 'AudioPlayerService', `Seeked to position: ${position}ms`);
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to seek: ${JSON.stringify(error)}`);
      this.handleError(`Seek failed: ${JSON.stringify(error)}`);
      throw new Error(`Seek failed: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 设置音量
   */
  public async setVolume(volume: number): Promise<void> {
    try {
      if (this.audioPlayer && volume >= 0 && volume <= 1) {
        await this.audioPlayer.setVolume(volume);
        hilog.info(DOMAIN, 'AudioPlayerService', `Volume set to: ${volume}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to set volume: ${JSON.stringify(error)}`);
      throw new Error(`Failed to set volume: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 获取当前播放状态
   */
  public getPlayState(): PlayState {
    return this.playState;
  }

  /**
   * 获取当前播放位置
   */
  public getCurrentPosition(): number {
    return this.currentPosition;
  }

  /**
   * 获取音频总时长
   */
  public getDuration(): number {
    return this.duration;
  }

  /**
   * 获取当前播放文件路径
   */
  public getCurrentFilePath(): string {
    return this.currentFilePath;
  }

  /**
   * 释放播放器资源
   */
  public async releasePlayer(): Promise<void> {
    try {
      this.stopProgressTimer();
      
      if (this.audioPlayer) {
        await this.audioPlayer.release();
        this.audioPlayer = null;
        hilog.info(DOMAIN, 'AudioPlayerService', 'Audio player released');
      }
      
      this.playState = PlayState.STOPPED;
      this.currentPosition = 0;
      this.duration = 0;
      this.currentFilePath = '';
      
    } catch (error) {
      hilog.error(DOMAIN, 'AudioPlayerService', `Failed to release player: ${JSON.stringify(error)}`);
      throw new Error(`Failed to release player: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 检查是否正在播放指定文件
   */
  public isPlayingFile(filePath: string): boolean {
    return this.currentFilePath === filePath && this.playState === PlayState.PLAYING;
  }

  /**
   * 检查是否暂停播放指定文件
   */
  public isPausedFile(filePath: string): boolean {
    return this.currentFilePath === filePath && this.playState === PlayState.PAUSED;
  }

  /**
   * 获取播放进度百分比
   */
  public getProgressPercentage(): number {
    if (this.duration === 0) {
      return 0;
    }
    return (this.currentPosition / this.duration) * 100;
  }

  /**
   * 根据百分比设置播放位置
   */
  public async seekToPercentage(percentage: number): Promise<void> {
    if (percentage >= 0 && percentage <= 100 && this.duration > 0) {
      const position = (percentage / 100) * this.duration;
      await this.seekTo(position);
    }
  }
}