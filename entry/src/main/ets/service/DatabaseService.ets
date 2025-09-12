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
    try {
      this.dataPreferences = await preferences.getPreferences(context, this.PREF_NAME);
      await this.initDefaultData();
      hilog.info(DOMAIN, TAG, 'Database initialized successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to initialize database: ${JSON.stringify(error)}`);
      throw new Error(`Failed to initialize database: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 初始化默认数据
   */
  private async initDefaultData(): Promise<void> {
    if (!this.dataPreferences) return;

    // 初始化分组数据
    const groups = await this.getAllGroups();
    if (groups.length === 0) {
      const defaultGroup: AudioGroup = {
        id: 1,
        groupName: '默认分组',
        createTime: Date.now(),
        audioCount: 0
      };
      await this.dataPreferences.put(this.GROUPS_KEY, JSON.stringify([defaultGroup]));
      await this.dataPreferences.put(this.NEXT_GROUP_ID_KEY, 2);
    }

    // 初始化记录数据
    const records = await this.getAllRecords();
    if (records.length === 0) {
      await this.dataPreferences.put(this.RECORDS_KEY, JSON.stringify([]));
      await this.dataPreferences.put(this.NEXT_RECORD_ID_KEY, 1);
    }

    await this.dataPreferences.flush();
  }

  /**
   * 获取所有记录
   */
  private async getAllRecords(): Promise<AudioRecord[]> {
    if (!this.dataPreferences) return [];
    
    const recordsStr = await this.dataPreferences.get(this.RECORDS_KEY, '[]') as string;
    return JSON.parse(recordsStr) as AudioRecord[];
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
    if (!this.dataPreferences) return;
    
    await this.dataPreferences.put(this.RECORDS_KEY, JSON.stringify(records));
    await this.dataPreferences.flush();
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
    
    const nextId = await this.dataPreferences.get(this.NEXT_GROUP_ID_KEY, 2) as number;
    await this.dataPreferences.put(this.NEXT_GROUP_ID_KEY, nextId + 1);
    await this.dataPreferences.flush();
    return nextId;
  }

  // ==================== 音频记录操作 ====================

  /**
   * 插入音频记录
   */
  public async insertAudioRecord(record: AudioRecordInput): Promise<number> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const newId = await this.getNextRecordId();
    
    const newRecord: AudioRecord = {
      id: newId,
      fileName: record.fileName,
      filePath: record.filePath,
      duration: record.duration,
      fileSize: record.fileSize,
      createTime: record.createTime,
      isTop: record.isTop,
      groupId: record.groupId || 1
    };

    records.push(newRecord);
    await this.saveRecords(records);
    
    // 更新分组音频数量
    if (newRecord.groupId) {
      await this.updateGroupAudioCount(newRecord.groupId);
    }

    return newId;
  }

  /**
   * 查询所有音频记录
   */
  public async queryAllAudioRecords(): Promise<AudioRecord[]> {
    const records = await this.getAllRecords();
    return records.sort((a, b) => {
      if (a.isTop !== b.isTop) {
        return b.isTop ? 1 : -1;
      }
      return b.createTime - a.createTime;
    });
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
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const recordIndex = records.findIndex(r => r.id === id);
    
    if (recordIndex !== -1) {
      const record = records[recordIndex];
      records.splice(recordIndex, 1);
      await this.saveRecords(records);
      
      // 更新分组音频数量
      if (record.groupId) {
        await this.updateGroupAudioCount(record.groupId);
      }
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

    // 不允许删除默认分组
    if (id === 1) {
      throw new Error('Cannot delete default group');
    }

    // 将该分组下的音频移到默认分组
    const records = await this.getAllRecords();
    records.forEach(record => {
      if (record.groupId === id) {
        record.groupId = 1;
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

    // 更新默认分组的音频数量
    await this.updateGroupAudioCount(1);
  }

  /**
   * 添加音频到分组
   */
  public async addAudioToGroup(audioId: number, groupId: number): Promise<void> {
    if (!this.dataPreferences) {
      throw new Error('Database not initialized');
    }

    const records = await this.getAllRecords();
    const record = records.find(r => r.id === audioId);
    
    if (record) {
      const oldGroupId = record.groupId;
      record.groupId = groupId;
      await this.saveRecords(records);
      
      // 更新相关分组的音频数量
      if (oldGroupId) {
        await this.updateGroupAudioCount(oldGroupId);
      }
      await this.updateGroupAudioCount(groupId);
    }
  }

  /**
   * 从分组移除音频（移到默认分组）
   */
  public async removeAudioFromGroup(audioId: number): Promise<void> {
    await this.addAudioToGroup(audioId, 1);
  }

  /**
   * 根据分组ID查询音频记录
   */
  public async queryAudioRecordsByGroup(groupId: number): Promise<AudioRecord[]> {
    const records = await this.getAllRecords();
    const filteredRecords = records.filter(record => record.groupId === groupId);
    
    return filteredRecords.sort((a, b) => {
      if (a.isTop !== b.isTop) {
        return b.isTop ? 1 : -1;
      }
      return b.createTime - a.createTime;
    });
  }

  /**
   * 更新分组音频数量
   */
  private async updateGroupAudioCount(groupId: number): Promise<void> {
    if (!this.dataPreferences) return;

    const records = await this.getAllRecords();
    const count = records.filter(record => record.groupId === groupId).length;
    
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