import hilog from '@ohos.hilog';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { DatabaseService } from '../service/DatabaseService';
import { AudioRecord, AudioGroup, TabType, MultiSelectState, DynamicTab } from '../model/DataModel';

const DOMAIN = 0xFF00;





@Entry
@Component
struct Index {
  @State private audioRecords: AudioRecord[] = [];
  @State private favoriteRecords: AudioRecord[] = [];
  @State private groupRecords: AudioRecord[] = [];
  @State private audioGroups: AudioGroup[] = [];
  @State private searchResults: AudioRecord[] = [];
  @State private currentTab: TabType = TabType.ALL;
  @State private currentGroupId: number = 0;
  @State private searchKeyword: string = '';
  @State private isSearchMode: boolean = false;
  @State private isLoading: boolean = false;
  @State private dynamicTabs: DynamicTab[] = [];
  @State private multiSelectState: MultiSelectState = {
    isMultiSelectMode: false,
    selectedRecords: new Set<number>()
  };
  @State private showGroupSelectionDialog: boolean = false;
  @State private showCreateGroupDialog: boolean = false;
  @State private showRenameGroupDialog: boolean = false;
  @State private showTabContextMenu: boolean = false;
  @State private newGroupName: string = '';
  @State private renameGroupName: string = '';
  @State private selectedTabForAction: DynamicTab | null = null;
  private longPressTimer: number = -1;
  private longPressTab: DynamicTab | null = null;

  private databaseService: DatabaseService = DatabaseService.getInstance();
  private context = getContext(this) as common.UIAbilityContext;

  aboutToAppear(): void {
    this.initializeData();
  }

  onPageShow(): void {
    // 🔥 关键修复：每次页面显示时都重新加载数据，确保显示最新的录音记录
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'Index', `[${timestamp}] onPageShow: 页面显示，当前isLoading状态: ${this.isLoading}`);
    
    if (this.isLoading) {
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 当前正在加载中，延迟500ms后重新加载数据`);
      setTimeout(() => {
        const retryTimestamp = new Date().toISOString();
        hilog.info(DOMAIN, 'Index', `[${retryTimestamp}] 延迟重新加载数据`);
        this.reloadAllData();
      }, 500);
    } else {
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 立即重新加载所有数据`);
      this.reloadAllData();
    }
  }

  /**
   * 重新加载所有数据
   */
  private async reloadAllData(): Promise<void> {
    const timestamp = new Date().toISOString();
    try {
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔄 开始重新加载音频记录`);
      await this.loadAudioRecords();
      hilog.info(DOMAIN, 'Index', `[${timestamp}] ✅ 音频记录加载完成，当前记录数: ${this.audioRecords.length}`);
      
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔄 开始重新加载音频分组`);
      await this.loadAudioGroups();
      hilog.info(DOMAIN, 'Index', `[${timestamp}] ✅ 音频分组加载完成，当前分组数: ${this.audioGroups.length}`);
      
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔄 开始重新初始化动态标签`);
      this.initializeDynamicTabs();
      hilog.info(DOMAIN, 'Index', `[${timestamp}] ✅ 动态标签初始化完成，当前标签数: ${this.dynamicTabs.length}`);
      
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🎉 所有数据重新加载完成！`);
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 当前显示的音频列表长度: ${this.getCurrentAudioList().length}`);
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `[${timestamp}] ❌ 重新加载数据时发生错误: ${JSON.stringify(error)}`);
    }
  }

  private async initializeData(): Promise<void> {
    try {
      this.isLoading = true;
      await this.databaseService.initDatabase(this.context);
      
      // 关键修复：启动时自动清理模拟数据
      hilog.info(DOMAIN, 'Index', 'Cleaning up mock data on startup...');
      await this.databaseService.cleanupMockData();
      
      // 加载音频记录和分组
      await this.loadAudioRecords();
      await this.loadAudioGroups();
      
      // 初始化动态标签
      this.initializeDynamicTabs();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to initialize data: ${JSON.stringify(error)}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载音频记录
   */
  private async loadAudioRecords(): Promise<void> {
    const timestamp = new Date().toISOString();
    try {
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔄 开始加载音频记录`);
      this.isLoading = true;
      
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 📞 调用数据库查询方法`);
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔍 数据库实例检查: ${this.databaseService ? '已初始化' : '未初始化'}`);
      const records = await this.databaseService.queryAllAudioRecords();
      
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 📊 从数据库获取到 ${records.length} 条音频记录`);
      
      if (records.length > 0) {
        hilog.info(DOMAIN, 'Index', `[${timestamp}] 📝 最新的3条记录详情:`);
        records.slice(0, 3).forEach((record, index) => {
          hilog.info(DOMAIN, 'Index', `[${timestamp}]   记录${index + 1}: ID=${record.id}, 文件名='${record.fileName}', 创建时间=${new Date(record.createTime).toLocaleString()}`);
        });
      } else {
        hilog.warn(DOMAIN, 'Index', `[${timestamp}] ⚠️ 没有获取到任何音频记录`);
      }
      
      this.audioRecords = records;
      hilog.info(DOMAIN, 'Index', `[${timestamp}] ✅ 音频记录已更新到页面状态，当前audioRecords长度: ${this.audioRecords.length}`);
      
      // 🔥 关键修复：强制触发UI更新
      setTimeout(() => {
        const uiUpdateTimestamp = new Date().toISOString();
        hilog.info(DOMAIN, 'Index', `[${uiUpdateTimestamp}] 🔄 强制触发UI更新，当前audioRecords长度: ${this.audioRecords.length}`);
        // 通过重新赋值触发状态更新
        this.audioRecords = [...this.audioRecords];
      }, 100);
      
      // 暂时移除收藏功能，后续会删除收藏tab
      this.favoriteRecords = [];
      if (this.currentTab === TabType.GROUP && this.currentGroupId) {
        // 🔥 多分组支持：从所有记录中筛选出指定分组的记录
        this.groupRecords = records.filter(record => {
          if (record.groupIds) {
            return record.groupIds.includes(this.currentGroupId);
          }
          // 兼容旧版本
          return record.groupId === this.currentGroupId;
        });
      }
      
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `[${timestamp}] ❌ 加载音频记录失败: ${JSON.stringify(error)}`);
    } finally {
      this.isLoading = false;
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🏁 音频记录加载完成，isLoading设为false`);
    }
  }

  private async loadAudioGroups(): Promise<void> {
    try {
      this.audioGroups = await this.databaseService.getAllGroups();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to load audio groups: ${JSON.stringify(error)}`);
    }
  }

  private async searchAudio(keyword: string): Promise<void> {
    if (keyword.trim() === '') {
      this.isSearchMode = false;
      this.searchResults = [];
      return;
    }

    this.isSearchMode = true;
    try {
      this.searchResults = await this.databaseService.searchAudioRecords(keyword);
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to search audio: ${JSON.stringify(error)}`);
    }
  }

  private onTabChange(tabType: TabType, groupId?: number): void {
    this.currentTab = tabType;
    this.currentGroupId = groupId || 0;
    this.exitMultiSelectMode();
    
    if (tabType === TabType.GROUP && groupId) {
      this.loadAudioRecords();
    }
  }

  private enterMultiSelectMode(initialRecordId?: number): void {
    this.multiSelectState = {
      isMultiSelectMode: true,
      selectedRecords: new Set<number>(initialRecordId ? [initialRecordId] : [])
    };
  }

  private exitMultiSelectMode(): void {
    this.multiSelectState = {
      isMultiSelectMode: false,
      selectedRecords: new Set<number>()
    };
  }

  private initializeDynamicTabs(): void {
    const timestamp = new Date().toISOString();
    
    // 🔥 关键修复：不使用扩展运算符，改用数组拼接
    const tabs: DynamicTab[] = [];
    
    // 添加"全部"标签
    tabs.push({ id: 0, type: TabType.ALL, name: '全部' });
    
    // 添加分组标签
    this.audioGroups.forEach((group, index) => {
      tabs.push({
        id: index + 1,
        type: TabType.GROUP,
        name: group.groupName,
        groupId: group.id
      });
    });
    
    this.dynamicTabs = tabs;
    
    hilog.info(DOMAIN, 'Index', `[${timestamp}] 🏷️ 动态标签初始化完成，共${tabs.length}个标签:`);
    this.dynamicTabs.forEach((tab, idx) => {
      hilog.info(DOMAIN, 'Index', `[${timestamp}]   Tab${idx}: name="${tab.name}", type=${tab.type} (${typeof tab.type}), groupId=${tab.groupId}`);
    });
    hilog.info(DOMAIN, 'Index', `[${timestamp}]   TabType.ALL=${TabType.ALL}, TabType.GROUP=${TabType.GROUP}`);
  }

  private showGroupSelectionDialogMethod(): void {
    this.showGroupSelectionDialog = true;
  }

  private async createNewGroup(): Promise<void> {
    if (this.newGroupName.trim() === '') return;

    try {
      await this.databaseService.createGroup(this.newGroupName.trim());
      await this.loadAudioGroups();
      this.initializeDynamicTabs();
      this.showCreateGroupDialog = false;
      this.newGroupName = '';
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to create group: ${JSON.stringify(error)}`);
    }
  }

  private async addToGroup(groupId: number): Promise<void> {
    const selectedIds = Array.from(this.multiSelectState.selectedRecords);
    if (selectedIds.length === 0) return;

    try {
      // 批量添加音频到分组
      for (const audioId of selectedIds) {
        await this.databaseService.addAudioToGroup(audioId, groupId);
      }
      await this.loadAudioRecords();
      this.exitMultiSelectMode();
      this.showGroupSelectionDialog = false;
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to add to group: ${JSON.stringify(error)}`);
    }
  }

  private selectExistingGroup(groupId: number): void {
    this.addToGroup(groupId);
  }

  private showRenameGroupDialogMethod(): void {
    if (this.selectedTabForAction && this.selectedTabForAction.type === TabType.GROUP) {
      this.renameGroupName = this.selectedTabForAction.name;
      this.showRenameGroupDialog = true;
      this.showTabContextMenu = false;
    }
  }

  private async renameGroup(): Promise<void> {
    if (!this.selectedTabForAction || !this.selectedTabForAction.groupId || this.renameGroupName.trim() === '') {
      return;
    }

    try {
      await this.databaseService.updateGroupName(this.selectedTabForAction.groupId, this.renameGroupName.trim());
      await this.loadAudioGroups();
      this.initializeDynamicTabs();
      this.showRenameGroupDialog = false;
      this.renameGroupName = '';
      this.selectedTabForAction = null;
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to rename group: ${JSON.stringify(error)}`);
    }
  }

  private async deleteGroup(): Promise<void> {
    if (!this.selectedTabForAction || !this.selectedTabForAction.groupId) return;

    try {
      await this.databaseService.deleteGroup(this.selectedTabForAction.groupId);
      await this.loadAudioGroups();
      this.initializeDynamicTabs();
      
      if (this.currentTab === TabType.GROUP && this.currentGroupId === this.selectedTabForAction.groupId) {
        this.onTabChange(TabType.ALL);
      }
      
      this.showTabContextMenu = false;
      this.selectedTabForAction = null;
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to delete group: ${JSON.stringify(error)}`);
    }
  }

  private getCurrentAudioList(): AudioRecord[] {
    const timestamp = new Date().toISOString();
    hilog.info(DOMAIN, 'Index', `[${timestamp}] 🎯 getCurrentAudioList() 被调用`);
    hilog.info(DOMAIN, 'Index', `[${timestamp}] 📊 当前状态: isSearchMode=${this.isSearchMode}, currentTab=${this.currentTab}`);
    
    let resultList: AudioRecord[] = [];
    
    if (this.isSearchMode) {
      resultList = this.searchResults;
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔍 搜索模式 - 返回搜索结果: ${resultList.length} 条记录`);
    } else {
      switch (this.currentTab) {
        case TabType.ALL:
          resultList = this.audioRecords;
          hilog.info(DOMAIN, 'Index', `[${timestamp}] 📋 全部标签 - 返回所有记录: ${resultList.length} 条记录`);
          break;
        case TabType.GROUP:
          resultList = this.groupRecords;
          hilog.info(DOMAIN, 'Index', `[${timestamp}] 👥 分组标签 - 返回分组记录: ${resultList.length} 条记录 (分组ID: ${this.currentGroupId})`);
          break;
        default:
          resultList = this.audioRecords;
          hilog.info(DOMAIN, 'Index', `[${timestamp}] 🔄 默认情况 - 返回所有记录: ${resultList.length} 条记录`);
          break;
      }
    }
    
    if (resultList.length > 0) {
      hilog.info(DOMAIN, 'Index', `[${timestamp}] 📝 返回列表的前3条记录:`);
      resultList.slice(0, 3).forEach((record, index) => {
        hilog.info(DOMAIN, 'Index', `[${timestamp}]   记录${index + 1}: ID=${record.id}, 文件名='${record.fileName}', 创建时间=${new Date(record.createTime).toLocaleString()}`);
      });
    } else {
      hilog.warn(DOMAIN, 'Index', `[${timestamp}] ⚠️ 返回的列表为空`);
    }
    
    return resultList;
  }

  private navigateToRecord(): void {
    router.pushUrl({ url: 'pages/RecordPage' });
  }

  private navigateToGroup(): void {
    router.pushUrl({ url: 'pages/GroupPage' });
  }

  private navigateToAudioDetail(audioRecord: AudioRecord): void {
    router.pushUrl({
      url: 'pages/AudioDetailPage',
      params: { audioId: audioRecord.id }
    });
  }

  private toggleRecordSelection(recordId: number): void {
    const newSelectedRecords = new Set(this.multiSelectState.selectedRecords);
    if (newSelectedRecords.has(recordId)) {
      newSelectedRecords.delete(recordId);
    } else {
      newSelectedRecords.add(recordId);
    }
    
    this.multiSelectState = {
      isMultiSelectMode: this.multiSelectState.isMultiSelectMode,
      selectedRecords: newSelectedRecords
    };
  }

  private async toggleTopStatus(audioRecord: AudioRecord): Promise<void> {
    try {
      await this.databaseService.toggleTopStatus(audioRecord.id, !audioRecord.isTop);
      await this.loadAudioRecords();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to toggle top status: ${JSON.stringify(error)}`);
    }
  }

  private formatDuration(duration: number): string {
    const seconds = Math.floor(duration / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  private formatFileSize(size: number): string {
    if (size < 1024) {
      return `${size}B`;
    } else if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)}KB`;
    } else {
      return `${(size / (1024 * 1024)).toFixed(1)}MB`;
    }
  }

  private formatCreateTime(timestamp: number): string {
    const date = new Date(timestamp);
    const now = new Date();
    const diffTime = now.getTime() - date.getTime();
    const diffDays = Math.floor(diffTime / (1000 * 60 * 60 * 24));

    if (diffDays === 0) {
      return `今天 ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    } else if (diffDays === 1) {
      return `昨天 ${date.getHours().toString().padStart(2, '0')}:${date.getMinutes().toString().padStart(2, '0')}`;
    } else if (diffDays < 7) {
      return `${diffDays}天前`;
    } else {
      return `${date.getMonth() + 1}/${date.getDate()}`;
    }
  }

  build() {
    Stack() {
      Column() {
        // 顶部标题栏
        Row() {
          Text('音频日记')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .backgroundColor('#FFFFFF')

        // 搜索框
        Row() {
          TextInput({ placeholder: '搜索音频文件', text: this.searchKeyword })
            .backgroundColor('transparent')
            .border({ width: 0 })
            .layoutWeight(1)
            .onChange((value: string) => {
              this.searchKeyword = value;
              this.searchAudio(value);
            })
        }
        .width('100%')
        .height(40)
        .padding({ left: 12, right: 12 })
        .margin({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#F8F8F8')
        .borderRadius(20)

        // Tab导航
        if (!this.isSearchMode) {
          Row() {
            ForEach(this.dynamicTabs, (tab: DynamicTab, index?: number) => {
              // 🔥 关键修复：同时使用手势和触摸事件，确保长按能被捕获
              Column() {
                Text(tab.name)
                  .fontSize(14)
                  .fontColor((this.currentTab === tab.type && this.currentGroupId === tab.groupId) ? '#007AFF' : '#666666')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              }
              .margin({ left: (index !== undefined && index > 0) ? 24 : 0 })
              .onClick(() => {
                // 清除长按定时器
                if (this.longPressTimer !== -1) {
                  clearTimeout(this.longPressTimer);
                  this.longPressTimer = -1;
                }
                
                hilog.info(DOMAIN, 'Index', `点击Tab: ${tab.name}, type=${tab.type}`);
                this.onTabChange(tab.type, tab.groupId);
              })
              .onTouch((event) => {
                if (tab.type !== TabType.GROUP) {
                  return;
                }
                
                if (event.type === TouchType.Down) {
                  // 开始长按计时
                  hilog.info(DOMAIN, 'Index', `👇 TouchDown on ${tab.name}`);
                  this.longPressTab = tab;
                  this.longPressTimer = setTimeout(() => {
                    hilog.info(DOMAIN, 'Index', `⏰ 长按触发: ${tab.name}`);
                    this.selectedTabForAction = tab;
                    this.showTabContextMenu = true;
                    this.longPressTimer = -1;
                  }, 500); // 500ms长按时间
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  // 取消长按计时
                  hilog.info(DOMAIN, 'Index', `👆 TouchUp/Cancel on ${tab.name}`);
                  if (this.longPressTimer !== -1) {
                    clearTimeout(this.longPressTimer);
                    this.longPressTimer = -1;
                  }
                }
              })
            })
            
            Blank()
          }
          .width('100%')
          .height(44)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
        }

        // 音频列表
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
              .color('#007AFF')
            
            Text('加载中...')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ top: 8 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          List() {
            ForEach(this.getCurrentAudioList(), (audioRecord: AudioRecord) => {
              ListItem() {
                this.AudioRecordItemBuilder(audioRecord)
              }
              .swipeAction({ end: this.SwipeActionsBuilder(audioRecord) })
            })
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor('#F8F8F8')
          .divider({
            strokeWidth: 0.5,
            color: '#E5E5E5',
            startMargin: 16,
            endMargin: 16
          })
        }

        // 多选模式操作栏
        if (this.multiSelectState.isMultiSelectMode) {
          Row() {
            Button('取消')
              .fontSize(14)
              .fontColor('#666666')
              .backgroundColor('transparent')
              .border({ width: 1, color: '#E5E5E5' })
              .borderRadius(8)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .onClick(() => this.exitMultiSelectMode())
            
            Blank()
            
            Text(`已选择 ${this.multiSelectState.selectedRecords.size} 项`)
              .fontSize(14)
              .fontColor('#666666')
            
            Blank()
            
            Button('添加到分组')
              .fontSize(14)
              .fontColor('#FFFFFF')
              .backgroundColor('#007AFF')
              .borderRadius(8)
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .enabled(this.multiSelectState.selectedRecords.size > 0)
              .onClick(() => this.showGroupSelectionDialogMethod())
          }
          .width('100%')
          .height(60)
          .padding({ left: 16, right: 16 })
          .backgroundColor('#FFFFFF')
          .border({ width: { top: 0.5 }, color: '#E5E5E5' })
        }

        // 底部录音按钮
        Row() {
          Button() {
            Image($r('app.media.record'))
              .width(50)
              .height(50)
              .fillColor('#FFFFFF')
          }
          .width(70)
          .height(70)
          .backgroundColor('#007AFF')
          .borderRadius(40)
          .onClick(() => this.navigateToRecord())
        }
        .width('100%')
        .height(80)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .backgroundColor('#FFFFFF')
      }
      .width('100%')
      .height('100%')

      // Tab长按菜单（居中显示的对话框样式）
      if (this.showTabContextMenu) {
        Stack() {
          // 半透明背景遮罩
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0, 0, 0, 0.4)')
            .onClick(() => {
              hilog.info(DOMAIN, 'Index', '点击遮罩关闭菜单');
              this.showTabContextMenu = false;
            })
          
          // 菜单内容
          Column() {
            Text(`分组: ${this.selectedTabForAction?.name || ''}`)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor('#333333')
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding({ top: 16, bottom: 12 })
            
            Divider()
              .color('#E5E5E5')
            
            Button('重命名')
              .fontSize(16)
              .fontColor('#333333')
              .backgroundColor('#FFFFFF')
              .width('100%')
              .height(50)
              .onClick(() => this.showRenameGroupDialogMethod())
            
            Divider()
              .color('#E5E5E5')
            
            Button('删除')
              .fontSize(16)
              .fontColor('#FF3B30')
              .backgroundColor('#FFFFFF')
              .width('100%')
              .height(50)
              .onClick(() => this.deleteGroup())
            
            Divider()
              .color('#E5E5E5')
              .strokeWidth(8)
            
            Button('取消')
              .fontSize(16)
              .fontColor('#007AFF')
              .backgroundColor('#FFFFFF')
              .width('100%')
              .height(50)
              .onClick(() => {
                this.showTabContextMenu = false;
              })
          }
          .width('80%')
          .backgroundColor('#FFFFFF')
          .borderRadius(12)
          .shadow({ radius: 16, color: 'rgba(0,0,0,0.3)' })
        }
        .width('100%')
        .height('100%')
      }

      // 选择分组弹窗
      if (this.showGroupSelectionDialog) {
        Column() {
          Text('选择分组')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 20 })
          
          List() {
            ForEach(this.audioGroups, (group: AudioGroup) => {
              ListItem() {
                Text(group.groupName)
                  .fontSize(16)
                  .fontColor('#333333')
                  .width('100%')
                  .height(44)
                  .textAlign(TextAlign.Start)
                  .onClick(() => this.selectExistingGroup(group.id))
              }
            })
            
            ListItem() {
              Text('+ 创建新分组')
                .fontSize(16)
                .fontColor('#007AFF')
                .width('100%')
                .height(44)
                .textAlign(TextAlign.Start)
                .onClick(() => {
                  this.showGroupSelectionDialog = false;
                  this.showCreateGroupDialog = true;
                })
            }
          }
          .width('100%')
          .height(200)
          
          Button('取消')
            .fontSize(16)
            .fontColor('#666666')
            .backgroundColor('#F5F5F5')
            .width('100%')
            .height(44)
            .margin({ top: 20 })
            .onClick(() => {
              this.showGroupSelectionDialog = false;
            })
        }
        .width('80%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.2)' })
        .position({ x: '10%', y: '30%' })
      }

      // 创建新分组弹窗
      if (this.showCreateGroupDialog) {
        Column() {
          Text('创建新分组')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 20 })
          
          TextInput({ placeholder: '请输入分组名称', text: this.newGroupName })
            .fontSize(16)
            .width('100%')
            .height(44)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .margin({ bottom: 20 })
            .onChange((value: string) => {
              this.newGroupName = value;
            })
          
          Row() {
            Button('取消')
              .fontSize(16)
              .fontColor('#666666')
              .backgroundColor('#F5F5F5')
              .width('48%')
              .height(44)
              .onClick(() => {
                this.showCreateGroupDialog = false;
                this.newGroupName = '';
              })
            
            Blank()
            
            Button('创建')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor('#007AFF')
              .width('48%')
              .height(44)
              .enabled(this.newGroupName.trim().length > 0)
              .onClick(() => this.createNewGroup())
          }
          .width('100%')
        }
        .width('80%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.2)' })
        .position({ x: '10%', y: '30%' })
      }

      // 重命名分组弹窗
      if (this.showRenameGroupDialog) {
        Column() {
          Text('重命名分组')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 20 })
          
          TextInput({ placeholder: '请输入新的分组名称', text: this.renameGroupName })
            .fontSize(16)
            .width('100%')
            .height(44)
            .backgroundColor('#F5F5F5')
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .margin({ bottom: 20 })
            .onChange((value: string) => {
              this.renameGroupName = value;
            })
          
          Row() {
            Button('取消')
              .fontSize(16)
              .fontColor('#666666')
              .backgroundColor('#F5F5F5')
              .width('48%')
              .height(44)
              .onClick(() => {
                this.showRenameGroupDialog = false;
                this.renameGroupName = '';
                this.selectedTabForAction = null;
              })
            
            Blank()
            
            Button('确定')
              .fontSize(16)
              .fontColor('#FFFFFF')
              .backgroundColor('#007AFF')
              .width('48%')
              .height(44)
              .enabled(this.renameGroupName.trim().length > 0)
              .onClick(() => this.renameGroup())
          }
          .width('100%')
        }
        .width('80%')
        .padding(20)
        .backgroundColor('#FFFFFF')
        .borderRadius(12)
        .shadow({ radius: 12, color: 'rgba(0,0,0,0.2)' })
        .position({ x: '10%', y: '30%' })
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  AudioRecordItemBuilder(audioRecord: AudioRecord) {
    Row() {
      if (this.multiSelectState.isMultiSelectMode) {
        Button()
        .width(24)
        .height(24)
        .padding(0)
        .backgroundColor(this.multiSelectState.selectedRecords.has(audioRecord.id) ? '#007AFF' : 'transparent')
        .border({ width: 2, color: '#007AFF' })
        .borderRadius(12)
        .margin({ right: 12 })
        .onClick(() => this.toggleRecordSelection(audioRecord.id))
      } else {
        // 移除按钮组件，保持布局间距
        Row()
        .width(12)
        .height(12)
        .margin({ right: 12 })
      }

      Column() {
        Row() {
          Text(audioRecord.fileName)
            .fontSize(16)
            .fontColor('#333333')
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          
          if (audioRecord.isTop) {
            Text('置顶')
              .fontSize(10)
              .fontColor('#FF6B35')
              .backgroundColor('#FFF3E0')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(8)
              .margin({ left: 8 })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Row() {
          Text(this.formatDuration(audioRecord.duration))
            .fontSize(12)
            .fontColor('#999999')
          
          Text('•')
            .fontSize(12)
            .fontColor('#999999')
            .margin({ left: 8, right: 8 })
          
          Text(this.formatFileSize(audioRecord.fileSize))
            .fontSize(12)
            .fontColor('#999999')
          
          Blank()
          
          Text(this.formatCreateTime(audioRecord.createTime))
            .fontSize(12)
            .fontColor('#999999')
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor('#FFFFFF')
    .onClick(() => {
      if (this.multiSelectState.isMultiSelectMode) {
        this.toggleRecordSelection(audioRecord.id);
      } else {
        this.navigateToAudioDetail(audioRecord);
      }
    })
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          if (!this.multiSelectState.isMultiSelectMode) {
            hilog.info(DOMAIN, 'Index', `长按音频项进入多选模式: ${audioRecord.fileName}`);
            this.enterMultiSelectMode(audioRecord.id);
          }
        })
    )
  }

  @Builder
  SwipeActionsBuilder(audioRecord: AudioRecord) {
    Row() {
      Button(audioRecord.isTop ? '取消置顶' : '置顶')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#FF9500')
        .width(80)
        .height('100%')
        .onClick(() => this.toggleTopStatus(audioRecord))
      
      Button('删除')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#FF3B30')
        .width(80)
        .height('100%')
        .onClick(async () => {
          try {
            await this.databaseService.deleteAudioRecord(audioRecord.id);
            await this.loadAudioRecords();
          } catch (error) {
            hilog.error(DOMAIN, 'Index', `Failed to delete audio record: ${JSON.stringify(error)}`);
          }
        })
    }
  }

  private loginWithHuaweiID(): void {
    const loginRequest = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    loginRequest.forceLogin = false;
    const controller = new authentication.AuthenticationController();
    controller.executeRequest(loginRequest).then((data: authentication.LoginWithHuaweiIDResponse) => {
      const loginWithHuaweiIDResponse = data;
      const authCode = loginWithHuaweiIDResponse.data?.authorizationCode;
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', 'error: %{public}s', JSON.stringify(error));
      if (error.code === authentication.AuthenticationErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        // HUAWEI ID is not logged in
      }
    });
  }
}