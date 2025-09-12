/**
 * 音频记录数据模型
 */
export interface AudioRecord {
  id: number;
  fileName: string;
  filePath: string;
  duration: number; // 时长，单位：毫秒
  fileSize: number; // 文件大小，单位：字节
  createTime: number; // 创建时间戳
  isTop: boolean; // 是否置顶
  groupId?: number; // 所属分组ID，可选
}

/**
 * 音频分组数据模型
 */
export interface AudioGroup {
  id: number;
  groupName: string;
  createTime: number; // 创建时间戳
  audioCount: number; // 分组内音频数量
}

/**
 * 录音状态枚举
 */
export enum RecordState {
  IDLE = 'idle',
  PREPARED = 'prepared',
  RECORDING = 'recording',
  PAUSED = 'paused',
  STOPPED = 'stopped',
  ERROR = 'error'
}

/**
 * 播放状态枚举
 */
export enum PlayState {
  IDLE = 'idle',
  PLAYING = 'playing',
  PAUSED = 'paused',
  STOPPED = 'stopped'
}

/**
 * Tab页面类型
 */
export enum TabType {
  ALL = 0,
  RECORD = 1,
  GROUP = 2
}

/**
 * 音频格式配置
 */
export interface AudioConfig {
  format: string; // 音频格式，如 'mp3', 'wav'
  sampleRate: number; // 采样率
  channels: number; // 声道数
  bitRate: number; // 比特率
}

/**
 * 录制器音频配置
 */
export interface RecorderAudioConfig {
  audioSourceType: number;
  audioEncoder: number;
  audioEncodeBitRate: number;
  audioSampleRate: number;
  numberOfChannels: number;
}

/**
 * 录制结果
 */
export interface RecordResult {
  filePath: string;
  duration: number;
  fileSize: number;
}

/**
 * 搜索结果
 */
export interface SearchResult {
  type: string;
  data: AudioRecord;
  matchText: string;
}