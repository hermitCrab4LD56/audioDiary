/**
 * 模拟录音配置接口
 */
interface MockRecordingConfig {
  minFileSize: number;
  maxFileSize: number;
  minAmplitude: number;
  maxAmplitude: number;
  amplitudeUpdateFrequency: number;
  fileExtension: string;
  mockAudioContent: string;
}

/**
 * 部署配置接口
 */
interface DeploymentConfig {
  needsRealPermissions: boolean;
  description: string;
}

/**
 * 开发模式配置
 * 用于控制开发环境和生产环境的行为差异
 */
export class DevConfig {
  // 开发模式标志 - 在生产环境中应设置为 false
  private static readonly IS_DEV_MODE: boolean = false;
  
  // 模拟录音配置
  private static readonly MOCK_RECORDING_CONFIG: MockRecordingConfig = {
    // 模拟录音文件大小范围（字节）
    minFileSize: 1024 * 10,  // 10KB
    maxFileSize: 1024 * 100, // 100KB
    
    // 模拟振幅范围
    minAmplitude: 5,
    maxAmplitude: 95,
    
    // 振幅变化频率（毫秒）
    amplitudeUpdateFrequency: 50,
    
    // 模拟录音文件扩展名
    fileExtension: '.m4a',
    
    // 模拟录音内容（Base64编码的空音频文件头）
    mockAudioContent: 'data:audio/mp4;base64,AAAAIGZ0eXBNNEEgAAACAGlzb21pc28yYXZjMW1wNDE='
  };
  
  /**
   * 检查是否为开发模式
   */
  public static isDevMode(): boolean {
    return DevConfig.IS_DEV_MODE;
  }
  
  /**
   * 检查是否为生产模式
   */
  public static isProdMode(): boolean {
    return !DevConfig.IS_DEV_MODE;
  }
  
  /**
   * 获取模拟录音配置
   */
  public static getMockRecordingConfig(): MockRecordingConfig {
    return DevConfig.MOCK_RECORDING_CONFIG;
  }
  
  /**
   * 生成模拟振幅值
   * @param baseTime 基准时间，用于生成变化的振幅
   * @returns 模拟的振幅值 (0-100)
   */
  public static generateMockAmplitude(baseTime: number = Date.now()): number {
    const config = DevConfig.MOCK_RECORDING_CONFIG;
    
    // 基于时间生成变化的振幅值，模拟真实录音
    const baseAmplitude = (config.minAmplitude + config.maxAmplitude) / 2;
    const amplitudeRange = config.maxAmplitude - config.minAmplitude;
    
    // 使用正弦波和随机数组合生成自然的振幅变化
    const sineWave = Math.sin(baseTime / 1000) * 0.3;
    const randomVariation = (Math.random() - 0.5) * 0.4;
    const normalizedAmplitude = 0.5 + sineWave + randomVariation;
    
    // 将归一化的振幅值映射到配置的范围内
    const amplitude = config.minAmplitude + (normalizedAmplitude * amplitudeRange);
    
    // 确保振幅值在有效范围内
    return Math.max(config.minAmplitude, Math.min(config.maxAmplitude, Math.round(amplitude)));
  }
  
  /**
   * 生成模拟文件大小
   * @param duration 录音时长（毫秒）
   * @returns 模拟的文件大小（字节）
   */
  public static generateMockFileSize(duration: number): number {
    const config = DevConfig.MOCK_RECORDING_CONFIG;
    
    // 基于时长计算文件大小（假设每秒约8KB的音频数据）
    const baseSizePerSecond = 8 * 1024; // 8KB/秒
    const calculatedSize = Math.round((duration / 1000) * baseSizePerSecond);
    
    // 添加一些随机变化，使其更真实
    const variation = calculatedSize * 0.1 * (Math.random() - 0.5);
    const finalSize = calculatedSize + variation;
    
    // 确保文件大小在合理范围内
    return Math.max(config.minFileSize, Math.min(config.maxFileSize, Math.round(finalSize)));
  }
  
  /**
   * 获取开发模式提示信息
   */
  public static getDevModeInfo(): string {
    if (DevConfig.isDevMode()) {
      return '当前运行在开发模式下，录音功能已模拟，无需真实权限';
    } else {
      return '当前运行在生产模式下，需要真实的录音权限';
    }
  }
  
  /**
   * 生产环境部署检查
   * 在生产环境中，此方法应该返回相关的部署配置信息
   */
  public static getDeploymentConfig(): DeploymentConfig {
    return {
      needsRealPermissions: DevConfig.isProdMode(),
      description: DevConfig.isProdMode() 
        ? '生产环境：需要真实的系统权限和录音功能'
        : '开发环境：使用模拟的录音功能，便于预览和测试'
    };
  }
}

/**
 * 开发模式工具类
 * 提供开发环境下的辅助功能
 */
export class DevUtils {
  /**
   * 开发模式日志
   * 只在开发模式下输出日志
   */
  public static devLog(tag: string, message: string): void {
    if (DevConfig.isDevMode()) {
      console.log(`[DEV-${tag}] ${message}`);
    }
  }
  
  /**
   * 开发模式警告
   * 只在开发模式下输出警告
   */
  public static devWarning(tag: string, message: string): void {
    if (DevConfig.isDevMode()) {
      console.warn(`[DEV-${tag}] ${message}`);
    }
  }
  
  /**
   * 开发模式错误
   * 只在开发模式下输出错误
   */
  public static devError(tag: string, message: string): void {
    if (DevConfig.isDevMode()) {
      console.error(`[DEV-${tag}] ${message}`);
    }
  }
  
  /**
   * 模拟延迟
   * 在开发模式下模拟异步操作的延迟
   */
  public static async mockDelay(ms: number = 100): Promise<void> {
    if (DevConfig.isDevMode()) {
      return new Promise(resolve => setTimeout(resolve, ms));
    }
  }
}