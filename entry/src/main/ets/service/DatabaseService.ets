import { preferences } from '@kit.ArkData';
import { AudioRecord, AudioGroup } from '../model/DataModel';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';

const TAG = 'DatabaseService';
const DOMAIN = 0x0000;

/**
 * 音频记录输入接口（不包含id字段）
 */
export interface AudioRecordInput {
  fileName: string;
  filePath: string;
  duration: number;
  fileSize: number;
  createTime: number;
  isTop: boolean;
  groupId?: number;
}

/**
 * 数据库服务类
 * 负责音频记录和分组的数据库操作
 * 使用preferences存储替代relationalStore
 */
export class DatabaseService {
  private static instance: DatabaseService;
  private dataPreferences: preferences.Preferences | null = null;
  private readonly PREF_NAME = 'AudioDiaryData';
  private readonly RECORDS_KEY = 'audio_records';
  private readonly GROUPS_KEY = 'audio_groups';
  private readonly NEXT_RECORD_ID_KEY = 'next_record_id';
  private readonly NEXT_GROUP_ID_KEY = 'next_group_id';

  private constructor() {}

  /**
   * 获取单例实例
   */
  public static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  /**
   * 初始化数据库
   */
  public async initDatabase(context: Context | common.UIAbilityContext): Promise<void> {
    const timestamp = new Date().toISOString();
    try {
      hilog.info(DOMAIN, TAG, `[${timestamp}] 🔄 开始初始化数据库`);
      
      this.dataPreferences = await preferences.getPreferences(context, this.PREF_NAME);
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ Preferences对象创建成功`);
      
      // 🔥 关键修复：验证preferences对象是否有效
      if (!this.dataPreferences) {
        throw new Error('Preferences对象创建失败，返回null');
      }
      
      await this.initDefaultData();
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 默认数据初始化完成`);
      
      // 🔥 关键修复：验证数据库是否真的可用
      const testRecords = await this.getAllRecords();
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 数据库验证成功，当前记录数: ${testRecords.length}`);
      
      hilog.info(DOMAIN, TAG, `[${timestamp}] 🎉 数据库初始化完全成功`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ 数据库初始化失败: ${JSON.stringify(error)}`);
      this.dataPreferences = null; // 确保清理状态
      throw new Error(`数据库初始化失败: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 初始化默认数据
   */
  private async initDefaultData(): Promise<void> {
    if (!this.dataPreferences) return;

    // 初始化分组数据 - 不创建默认分组，让用户自己创建
    const groups = await this.getAllGroups();
    if (groups.length === 0) {
      await this.dataPreferences.put(this.GROUPS_KEY, JSON.stringify([]));
      await this.dataPreferences.put(this.NEXT_GROUP_ID_KEY, 1);
    }

    // 初始化记录数据并进行数据迁移
    const records = await this.getAllRecords();
    if (records.length === 0) {
      await this.dataPreferences.put(this.RECORDS_KEY, JSON.stringify([]));
      await this.dataPreferences.put(this.NEXT_RECORD_ID_KEY, 1);
    } else {
      // 🔥 数据迁移：将旧的groupId转换为groupIds数组
      let needsMigration = false;
      const migratedRecords = records.map(record => {
        if (record.groupId !== undefined && !record.groupIds) {
          needsMigration = true;
          // 如果有groupId但没有groupIds，进行迁移
          const migratedRecord: AudioRecord = {
            id: record.id,
            fileName: record.fileName,
            filePath: record.filePath,
            duration: record.duration,
            fileSize: record.fileSize,
            createTime: record.createTime,
            isTop: record.isTop,
            groupId: record.groupId,
            groupIds: record.groupId ? [record.groupId] : []
          };
          return migratedRecord;
        } else if (!record.groupIds) {
          // 如果既没有groupId也没有groupIds，初始化为空数组
          needsMigration = true;
          const migratedRecord: AudioRecord = {
            id: record.id,
            fileName: record.fileName,
            filePath: record.filePath,
            duration: record.duration,
            fileSize: record.fileSize,
            createTime: record.createTime,
            isTop: record.isTop,
            groupId: record.groupId,
            groupIds: []
          };
          return migratedRecord;
        }
        return record;
      });
      
      if (needsMigration) {
        hilog.info(DOMAIN, TAG, '执行数据迁移：groupId -> groupIds');
        await this.saveRecords(migratedRecords);
      }
    }

    await this.dataPreferences.flush();
  }

  /**
   * 获取所有记录
   */
  private async getAllRecords(): Promise<AudioRecord[]> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 🔍 getAllRecords() 开始从数据库读取记录`);
    
    if (!this.dataPreferences) {
      hilog.warn(DOMAIN, TAG, `[${timestamp}] ⚠️ dataPreferences未初始化，返回空数组`);
      return [];
    }
    
    hilog.info(DOMAIN, TAG, `[${timestamp}] 📞 调用dataPreferences.get()读取记录数据`);
    const recordsStr = await this.dataPreferences.get(this.RECORDS_KEY, '[]') as string;
    hilog.info(DOMAIN, TAG, `[${timestamp}] 📊 从存储中获取到的原始数据长度: ${recordsStr.length}字符`);
    hilog.info(DOMAIN, TAG, `[${timestamp}] 📝 原始数据内容预览: ${recordsStr.substring(0, 200)}${recordsStr.length > 200 ? '...' : ''}`);
    
    try {
      const records = JSON.parse(recordsStr) as AudioRecord[];
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ JSON解析成功，获取到 ${records.length} 条记录`);
      
      if (records.length > 0) {
        hilog.info(DOMAIN, TAG, `[${timestamp}] 📋 记录详情预览:`);
        records.slice(0, 2).forEach((record, index) => {
          hilog.info(DOMAIN, TAG, `[${timestamp}]   记录${index + 1}: ID=${record.id}, 文件名='${record.fileName}', 时长=${record.duration}ms`);
        });
      }
      
      return records;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ JSON解析失败: ${JSON.stringify(error)}`);
      hilog.error(DOMAIN, TAG, `[${timestamp}] 原始数据: ${recordsStr}`);
      return [];
    }
  }

  /**
   * 获取所有分组
   */
  public async getAllGroups(): Promise<AudioGroup[]> {
    if (!this.dataPreferences) return [];
    
    const groupsStr = await this.dataPreferences.get(this.GROUPS_KEY, '[]') as string;
    return JSON.parse(groupsStr) as AudioGroup[];
  }

  /**
   * 保存记录
   */
  private async saveRecords(records: AudioRecord[]): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 💾 saveRecords() started, saving ${records.length} records`);
    
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ Database not initialized`);
      return;
    }
    
    try {
      const recordsJson = JSON.stringify(records);
      hilog.info(DOMAIN, TAG, `[${timestamp}] 📝 JSON data length: ${recordsJson.length} characters`);
      
      await this.dataPreferences.put(this.RECORDS_KEY, recordsJson);
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ Records saved to preferences`);
      
      await this.dataPreferences.flush();
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ Data flushed to storage`);
      
      // 🔥 关键修复：验证数据是否真的被保存
      const verifyJson = await this.dataPreferences.get(this.RECORDS_KEY, '');
      if (verifyJson === recordsJson) {
        hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 数据保存验证成功`);
      } else {
        hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ 数据保存验证失败`);
      }
      
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ Failed to save records: ${JSON.stringify(error)}`);
      throw new Error(`Failed to save records: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 保存分组
   */
  private async saveGroups(groups: AudioGroup[]): Promise<void> {
    if (!this.dataPreferences) return;
    
    await this.dataPreferences.put(this.GROUPS_KEY, JSON.stringify(groups));
    await this.dataPreferences.flush();
  }

  /**
   * 获取下一个记录ID
   */
  private async getNextRecordId(): Promise<number> {
    if (!this.dataPreferences) return 1;
    
    const nextId = await this.dataPreferences.get(this.NEXT_RECORD_ID_KEY, 1) as number;
    await this.dataPreferences.put(this.NEXT_RECORD_ID_KEY, nextId + 1);
    await this.dataPreferences.flush();
    return nextId;
  }

  /**
   * 获取下一个分组ID
   */
  private async getNextGroupId(): Promise<number> {
    if (!this.dataPreferences) return 1;
    
    const nextId = await this.dataPreferences.get(this.NEXT_GROUP_ID_KEY, 1) as number;
    await this.dataPreferences.put(this.NEXT_GROUP_ID_KEY, nextId + 1);
    await this.dataPreferences.flush();
    return nextId;
  }

  // ==================== 音频记录操作 ====================

  /**
   * 插入音频记录
   */
  public async insertAudioRecord(record: AudioRecordInput): Promise<number> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] insertAudioRecord() started, params: ${JSON.stringify(record)}`);
    
    // 🔥 关键修复：验证数据库连接状态
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ Database not initialized - dataPreferences is null`);
      throw new Error('Database not initialized - dataPreferences is null');
    }
    
    // 🔥 关键修复：测试数据库连接是否可用
    try {
      await this.dataPreferences.flush();
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 数据库连接验证成功`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ 数据库连接验证失败: ${JSON.stringify(error)}`);
      throw new Error(`数据库连接不可用: ${JSON.stringify(error)}`);
    }
    hilog.info(DOMAIN, TAG, `[${timestamp}] Database initialized, starting to get all records`);

    const records = await this.getAllRecords();
    hilog.info(DOMAIN, TAG, `[${timestamp}] Got ${records.length} existing records`);
    
    const newId = await this.getNextRecordId();
    hilog.info(DOMAIN, TAG, `[${timestamp}] Generated new record ID: ${newId}`);
    
    const newRecord: AudioRecord = {
      id: newId,
      fileName: record.fileName,
      filePath: record.filePath,
      duration: record.duration,
      fileSize: record.fileSize,
      createTime: record.createTime,
      isTop: record.isTop,
      groupId: record.groupId || 0, // 0表示未分组（向后兼容）
      groupIds: record.groupId ? [record.groupId] : [] // 🔥 多分组支持：初始化groupIds数组
    };
    hilog.info(DOMAIN, TAG, `[${timestamp}] Created new record object: ${JSON.stringify(newRecord)}`);

    records.push(newRecord);
    hilog.info(DOMAIN, TAG, `[${timestamp}] Added new record to list, current total: ${records.length}`);
    
    await this.saveRecords(records);
    hilog.info(DOMAIN, TAG, `[${timestamp}] Record saved successfully`);
    
    // 🔥 关键修复：立即验证数据是否真的被保存
    const verifyRecords = await this.getAllRecords();
    const savedRecord = verifyRecords.find(r => r.id === newId);
    if (savedRecord) {
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 数据保存验证成功，找到新保存的记录: ID=${savedRecord.id}, 文件名='${savedRecord.fileName}'`);
    } else {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ 数据保存验证失败，未找到新保存的记录！`);
      throw new Error('数据保存验证失败');
    }
    
    // 更新分组音频数量
    if (newRecord.groupId) {
      hilog.info(DOMAIN, TAG, `[${timestamp}] Starting to update audio count for group ${newRecord.groupId}`);
      await this.updateGroupAudioCount(newRecord.groupId);
      hilog.info(DOMAIN, TAG, `[${timestamp}] Group audio count update completed`);
    }

    hilog.info(DOMAIN, TAG, `[${timestamp}] insertAudioRecord() executed successfully, returning ID: ${newId}`);
    return newId;
  }

  /**
   * 查询所有音频记录
   */
  public async queryAllAudioRecords(): Promise<AudioRecord[]> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 🔍 queryAllAudioRecords() 开始查询所有音频记录`);
    
    // 🔥 关键修复：强制刷新数据存储，确保获取最新数据
    if (this.dataPreferences) {
      await this.dataPreferences.flush();
      hilog.info(DOMAIN, TAG, `[${timestamp}] 💾 强制刷新数据存储完成`);
    }
    
    const records = await this.getAllRecords();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 📊 从数据库获取到 ${records.length} 条音频记录`);
    
    if (records.length > 0) {
      hilog.info(DOMAIN, TAG, `[${timestamp}] 📝 最新的3条记录详情:`);
      records.slice(0, 3).forEach((record, index) => {
        hilog.info(DOMAIN, TAG, `[${timestamp}] 记录${index + 1}: ID=${record.id}, 文件名='${record.fileName}', 创建时间=${new Date(record.createTime).toLocaleString()}`);
      });
    } else {
      hilog.warn(DOMAIN, TAG, `[${timestamp}] ⚠️ 数据库中没有找到任何音频记录`);
    }
    
    const sortedRecords = records.sort((a, b) => {
      if (a.isTop !== b.isTop) {
        return b.isTop ? 1 : -1;
      }
      return b.createTime - a.createTime;
    });
    
    hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 音频记录排序完成，返回 ${sortedRecords.length} 条记录`);
    return sortedRecords;
  }

  /**
   * 根据关键词搜索音频记录
   */
  public async searchAudioRecords(keyword: string): Promise<AudioRecord[]> {
    const records = await this.getAllRecords();
    const filteredRecords = records.filter(record => 
      record.fileName.toLowerCase().includes(keyword.toLowerCase())
    );
    
    return filteredRecords.sort((a, b) => {
      if (a.isTop !== b.isTop) {
        return b.isTop ? 1 : -1;
      }
      return b.createTime - a.createTime;
    });
  }

  /**
   * 更新音频记录
   */
  public async updateAudioRecord(record: AudioRecord): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const index = records.findIndex(r => r.id === record.id);
    
    if (index !== -1) {
      records[index] = record;
      await this.saveRecords(records);
    }
  }

  /**
   * 删除音频记录
   */
  public async deleteAudioRecord(id: number): Promise<void> {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 🗑️ deleteAudioRecord() started, ID: ${id}`);
    
    if (!this.dataPreferences) {
      hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ Database not initialized`);
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    hilog.info(DOMAIN, TAG, `[${timestamp}] 📊 当前数据库中有 ${records.length} 条记录`);
    
    const recordIndex = records.findIndex(r => r.id === id);
    
    if (recordIndex !== -1) {
      const record = records[recordIndex];
      hilog.info(DOMAIN, TAG, `[${timestamp}] 📝 找到要删除的记录: ID=${record.id}, 文件名='${record.fileName}'`);
      
      records.splice(recordIndex, 1);
      hilog.info(DOMAIN, TAG, `[${timestamp}] 🗂️ 从列表中移除记录，剩余 ${records.length} 条记录`);
      
      await this.saveRecords(records);
      hilog.info(DOMAIN, TAG, `[${timestamp}] 💾 记录已保存到数据库`);
      
      // 🔥 关键修复：立即验证删除是否成功
      const verifyRecords = await this.getAllRecords();
      const deletedRecord = verifyRecords.find(r => r.id === id);
      if (!deletedRecord) {
        hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ 删除验证成功，记录已不存在`);
      } else {
        hilog.error(DOMAIN, TAG, `[${timestamp}] ❌ 删除验证失败，记录仍然存在`);
      }
      
      // 更新分组音频数量
      if (record.groupId) {
        hilog.info(DOMAIN, TAG, `[${timestamp}] 📊 更新分组 ${record.groupId} 的音频数量`);
        await this.updateGroupAudioCount(record.groupId);
      }
      
      hilog.info(DOMAIN, TAG, `[${timestamp}] ✅ deleteAudioRecord() completed successfully`);
    } else {
      hilog.warn(DOMAIN, TAG, `[${timestamp}] ⚠️ 未找到ID为 ${id} 的记录`);
    }
  }

  /**
   * 切换置顶状态
   */
  public async toggleTopStatus(id: number, isTop: boolean): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const record = records.find(r => r.id === id);
    
    if (record) {
      record.isTop = isTop;
      await this.saveRecords(records);
    }
  }

  /**
   * 根据ID获取音频记录
   */
  public async getAudioRecordById(id: number): Promise<AudioRecord | null> {
    const records = await this.getAllRecords();
    return records.find(r => r.id === id) || null;
  }

  /**
   * 清理损坏的数据（修复重复记录和错误分组）
   */
  public async cleanupCorruptedData(): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    hilog.info(DOMAIN, TAG, 'Starting data cleanup...');
    
    // 首先清理模拟数据
    await this.cleanupMockData();
    
    // 清理重复的音频记录
    const records = await this.getAllRecords();
    const uniqueRecords = new Map<string, AudioRecord>();
    
    // 使用文件路径作为唯一标识，保留最新的记录
    records.forEach(record => {
      const key = record.filePath;
      if (!uniqueRecords.has(key) || record.createTime > uniqueRecords.get(key)!.createTime) {
        uniqueRecords.set(key, record);
      }
    });
    
    const cleanedRecords = Array.from(uniqueRecords.values());
    hilog.info(DOMAIN, TAG, `Removed ${records.length - cleanedRecords.length} duplicate records`);
    
    // 清理无效的分组（只保留有音频记录的分组）
    const groups = await this.getAllGroups();
    const validGroupIds = new Set(cleanedRecords.map(r => r.groupId).filter(id => id && id > 0));
    const cleanedGroups = groups.filter(group => validGroupIds.has(group.id));
    
    hilog.info(DOMAIN, TAG, `Removed ${groups.length - cleanedGroups.length} invalid groups`);
    
    // 保存清理后的数据
    await this.saveRecords(cleanedRecords);
    await this.saveGroups(cleanedGroups);
    
    // 重新计算分组音频数量
    for (const group of cleanedGroups) {
      await this.updateGroupAudioCount(group.id);
    }
    
    hilog.info(DOMAIN, TAG, 'Data cleanup completed successfully');
  }

  /**
   * 清理模拟数据
   * 删除包含模拟、测试、示例等关键词的音频记录
   */
  public async cleanupMockData(): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    hilog.info(DOMAIN, TAG, 'Starting mock data cleanup...');
    
    const records = await this.getAllRecords();
    const mockKeywords = ['mock', 'test', 'sample', '模拟', '测试', '示例', '演示'];
    
    // 过滤掉包含模拟关键词的记录
    const realRecords = records.filter(record => {
      const fileName = record.fileName.toLowerCase();
      const filePath = record.filePath.toLowerCase();
      
      // 检查文件名和路径是否包含模拟关键词
      return !mockKeywords.some(keyword => 
        fileName.includes(keyword) || filePath.includes(keyword)
      );
    });
    
    const removedCount = records.length - realRecords.length;
    if (removedCount > 0) {
      await this.saveRecords(realRecords);
      hilog.info(DOMAIN, TAG, `Removed ${removedCount} mock data records`);
    } else {
      hilog.info(DOMAIN, TAG, 'No mock data found to clean');
    }
  }

  /**
   * 清理所有数据（用于调试和重置）
   */
  public async clearAllData(): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    // 清空所有记录和分组
    await this.dataPreferences.put(this.RECORDS_KEY, JSON.stringify([]));
    await this.dataPreferences.put(this.GROUPS_KEY, JSON.stringify([]));
    
    // 重置ID计数器
    await this.dataPreferences.put(this.NEXT_RECORD_ID_KEY, 1);
    await this.dataPreferences.put(this.NEXT_GROUP_ID_KEY, 1);
    
    await this.dataPreferences.flush();
    hilog.info(DOMAIN, TAG, 'All data cleared successfully');
  }

  // ==================== 音频分组操作 ====================

  /**
   * 创建分组
   */
  public async createGroup(groupName: string): Promise<number> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const groups = await this.getAllGroups();
    const newId = await this.getNextGroupId();
    
    const newGroup: AudioGroup = {
      id: newId,
      groupName: groupName,
      createTime: Date.now(),
      audioCount: 0
    };

    groups.push(newGroup);
    await this.saveGroups(groups);
    
    return newId;
  }

  /**
   * 查询所有分组
   */
  public async queryAllGroups(): Promise<AudioGroup[]> {
    const groups = await this.getAllGroups();
    return groups.sort((a, b) => b.createTime - a.createTime);
  }

  /**
   * 更新分组名称
   */
  public async updateGroupName(id: number, newName: string): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const groups = await this.getAllGroups();
    const group = groups.find(g => g.id === id);
    
    if (group) {
      group.groupName = newName;
      await this.saveGroups(groups);
    }
  }

  /**
   * 删除分组
   */
  public async deleteGroup(id: number): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    // 🔥 多分组支持：从所有音频的groupIds中移除该分组ID
    const records = await this.getAllRecords();
    records.forEach(record => {
      // 处理新版本的groupIds数组
      if (record.groupIds && record.groupIds.includes(id)) {
        record.groupIds = record.groupIds.filter(gid => gid !== id);
      }
      // 兼容旧版本的groupId
      if (record.groupId === id) {
        record.groupId = undefined;
      }
    });
    await this.saveRecords(records);

    // 删除分组
    const groups = await this.getAllGroups();
    const groupIndex = groups.findIndex(g => g.id === id);
    if (groupIndex !== -1) {
      groups.splice(groupIndex, 1);
      await this.saveGroups(groups);
    }
  }

  /**
   * 添加音频到分组（支持多分组，不会移除其他分组）
   */
  public async addAudioToGroup(audioId: number, groupId: number): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const record = records.find(r => r.id === audioId);
    
    if (record) {
      // 🔥 多分组支持：添加到groupIds数组
      if (!record.groupIds) {
        record.groupIds = [];
      }
      
      // 如果该分组不在列表中，则添加
      if (!record.groupIds.includes(groupId)) {
        record.groupIds.push(groupId);
        await this.saveRecords(records);
        
        // 更新分组的音频数量
        await this.updateGroupAudioCount(groupId);
      }
    }
  }

  /**
   * 从分组移除音频
   */
  public async removeAudioFromGroup(audioId: number, groupId: number): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const record = records.find(r => r.id === audioId);
    
    if (record && record.groupIds) {
      // 🔥 多分组支持：从groupIds数组中移除指定分组
      record.groupIds = record.groupIds.filter(gid => gid !== groupId);
      await this.saveRecords(records);
      
      // 更新分组的音频数量
      await this.updateGroupAudioCount(groupId);
    }
  }

  /**
   * 根据分组ID查询音频记录（支持多分组）
   */
  public async queryAudioRecordsByGroup(groupId: number): Promise<AudioRecord[]> {
    const records = await this.getAllRecords();
    
    // 🔥 多分组支持：检查groupIds数组是否包含该分组ID
    const filteredRecords = records.filter(record => {
      // 优先使用新版本的groupIds
      if (record.groupIds) {
        return record.groupIds.includes(groupId);
      }
      // 兼容旧版本的groupId
      return record.groupId === groupId;
    });
    
    return filteredRecords.sort((a, b) => {
      if (a.isTop !== b.isTop) {
        return b.isTop ? 1 : -1;
      }
      return b.createTime - a.createTime;
    });
  }

  /**
   * 更新分组音频数量（支持多分组）
   */
  private async updateGroupAudioCount(groupId: number): Promise<void> {
    if (!this.dataPreferences) return;

    const records = await this.getAllRecords();
    
    // 🔥 多分组支持：统计groupIds中包含该分组ID的记录数
    const count = records.filter(record => {
      if (record.groupIds) {
        return record.groupIds.includes(groupId);
      }
      // 兼容旧版本
      return record.groupId === groupId;
    }).length;
    
    const groups = await this.getAllGroups();
    const group = groups.find(g => g.id === groupId);
    
    if (group) {
      group.audioCount = count;
      await this.saveGroups(groups);
    }
  }

  /**
   * 关闭数据库
   */
  public async closeDatabase(): Promise<void> {
    // preferences不需要显式关闭
    this.dataPreferences = null;
  }
}