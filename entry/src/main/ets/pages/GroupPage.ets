import { router } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { AudioGroup, AudioRecord } from '../model/DataModel';
import { DatabaseService } from '../service/DatabaseService';
import { promptAction } from '@kit.ArkUI';

const DOMAIN = 0x0000;

@Entry
@Component
struct GroupPage {
  @State groups: AudioGroup[] = [];
  @State isLoading: boolean = false;
  @State isShowCreateDialog: boolean = false;
  @State isShowEditDialog: boolean = false;
  @State isShowDeleteDialog: boolean = false;
  @State newGroupName: string = '';
  @State editingGroup: AudioGroup | null = null;
  @State deletingGroup: AudioGroup | null = null;
  @State searchText: string = '';
  @State filteredGroups: AudioGroup[] = [];
  
  private databaseService = DatabaseService.getInstance();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
  private createDialogController: CustomDialogController | null = null;
  private editDialogController: CustomDialogController | null = null;
  private deleteDialogController: CustomDialogController | null = null;

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, 'GroupPage', 'Page aboutToAppear');
    await this.initializePage();
  }

  aboutToDisappear(): void {
    hilog.info(DOMAIN, 'GroupPage', 'Page aboutToDisappear');
    this.closeAllDialogs();
  }

  /**
   * 初始化页面
   */
  private async initializePage(): Promise<void> {
    try {
      // 初始化数据库
      await this.databaseService.initDatabase(this.context);
      
      // 加载分组数据
      await this.loadGroups();
      
    } catch (error) {
      hilog.error(DOMAIN, 'GroupPage', `Failed to initialize page: ${JSON.stringify(error)}`);
      this.showToast('初始化页面失败');
    }
  }

  /**
   * 加载分组列表
   */
  private async loadGroups(): Promise<void> {
    try {
      this.isLoading = true;
      this.groups = await this.databaseService.getAllGroups();
      this.filterGroups();
      hilog.info(DOMAIN, 'GroupPage', `Loaded ${this.groups.length} groups`);
    } catch (error) {
      hilog.error(DOMAIN, 'GroupPage', `Failed to load groups: ${JSON.stringify(error)}`);
      this.showToast('Failed to load groups');
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 过滤分组
   */
  private filterGroups(): void {
    if (!this.searchText.trim()) {
      this.filteredGroups = this.groups.slice();
    } else {
      const searchLower = this.searchText.toLowerCase();
      this.filteredGroups = this.groups.filter((group: AudioGroup): boolean => {
        return group.groupName.toLowerCase().includes(searchLower);
      });
    }
  }

  /**
   * 搜索分组
   */
  private onSearchTextChange(text: string): void {
    this.searchText = text;
    this.filterGroups();
  }

  /**
   * 显示创建分组对话框
   */
  private showCreateGroupDialog(): void {
    this.newGroupName = '';
    this.createDialogController = new CustomDialogController({
      builder: CreateGroupDialog({
        groupName: this.newGroupName,
        onConfirm: (name: string) => this.createGroup(name),
        onCancel: () => this.closeCreateDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.createDialogController.open();
  }

  /**
   * 显示编辑分组对话框
   */
  private showEditGroupDialog(group: AudioGroup): void {
    this.editingGroup = group;
    this.newGroupName = group.groupName;
    this.editDialogController = new CustomDialogController({
      builder: EditGroupDialog({
        groupName: this.newGroupName,
        onConfirm: (name: string) => this.updateGroupName(group, name),
        onCancel: () => this.closeEditDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.editDialogController.open();
  }

  /**
   * 显示删除确认对话框
   */
  private showDeleteConfirmDialog(group: AudioGroup): void {
    this.deletingGroup = group;
    this.deleteDialogController = new CustomDialogController({
      builder: DeleteConfirmDialog({
        groupName: group.groupName,
        onConfirm: () => this.deleteGroup(group),
        onCancel: () => this.closeDeleteDialog()
      }),
      autoCancel: false,
      alignment: DialogAlignment.Center
    });
    this.deleteDialogController.open();
  }

  /**
   * 创建分组
   */
  private async createGroup(name: string): Promise<void> {
    try {
      if (!name.trim()) {
        this.showToast('Group name cannot be empty');
        return;
      }

      // 检查分组名是否已存在
      const existingGroup = this.groups.find(group => group.groupName === name.trim());
      if (existingGroup) {
        this.showToast('分组名称已存在');
        return;
      }

      const groupId = await this.databaseService.createGroup(name.trim());
      
      const newGroup: AudioGroup = {
        id: groupId,
        groupName: name.trim(),
        createTime: Date.now(),
        audioCount: 0
      };

      
      this.groups.unshift(newGroup);
      this.filterGroups();
      
      this.showToast('Group created successfully');
      this.closeCreateDialog();
      
      hilog.info(DOMAIN, 'GroupPage', `Group created: ${name}`);
    } catch (error) {
      hilog.error(DOMAIN, 'GroupPage', `Failed to create group: ${JSON.stringify(error)}`);
      this.showToast('Failed to create group');
    }
  }

  /**
   * 更新分组名称
   */
  private async updateGroupName(group: AudioGroup, newName: string): Promise<void> {
    try {
      if (!newName.trim()) {
        this.showToast('请输入分组名称');
        return;
      }

      // 检查分组名是否已存在（排除当前分组）
      const existingGroup = this.groups.find(g => g.groupName === newName.trim() && g.id !== group.id);
      if (existingGroup) {
        this.showToast('分组名称已存在');
        return;
      }

      await this.databaseService.updateGroupName(group.id, newName.trim());
      
      // 更新本地数据
      const updatedGroup: AudioGroup = {
        id: group.id,
        groupName: newName.trim(),
        createTime: group.createTime,
        audioCount: group.audioCount
      };
      
      // 更新本地数据
      const index = this.groups.findIndex(g => g.id === group.id);
      if (index !== -1) {
        this.groups[index] = updatedGroup;
        this.filterGroups();
      }
      
      this.showToast('分组更新成功');
      this.closeEditDialog();
      
      hilog.info(DOMAIN, 'GroupPage', `Group updated: ${group.groupName} -> ${newName}`);
    } catch (error) {
      hilog.error(DOMAIN, 'GroupPage', `Failed to update group: ${JSON.stringify(error)}`);
      this.showToast('更新分组失败');
    }
  }

  /**
   * 删除分组
   */
  private async deleteGroup(group: AudioGroup): Promise<void> {
    try {
      await this.databaseService.deleteGroup(group.id);
      
      // 从本地数据中移除
      const index = this.groups.findIndex(g => g.id === group.id);
      if (index !== -1) {
        this.groups.splice(index, 1);
        this.filterGroups();
      }
      
      this.showToast('分组删除成功');
      this.closeDeleteDialog();
      
      hilog.info(DOMAIN, 'GroupPage', `Group deleted: ${group.groupName}`);
    } catch (error) {
      hilog.error(DOMAIN, 'GroupPage', `Failed to delete group: ${JSON.stringify(error)}`);
      this.showToast('删除分组失败');
    }
  }

  /**
   * 查看分组详情
   */
  private viewGroupDetail(group: AudioGroup): void {
    router.pushUrl({
      url: 'pages/GroupDetailPage',
      params: {
        groupId: group.id,
        groupName: group.groupName
      }
    }).catch((error: Error) => {
      hilog.error(DOMAIN, 'GroupPage', `Failed to navigate to group detail: ${JSON.stringify(error)}`);
      this.showToast('打开分组详情失败');
    });
  }

  /**
   * 关闭所有对话框
   */
  private closeAllDialogs(): void {
    this.closeCreateDialog();
    this.closeEditDialog();
    this.closeDeleteDialog();
  }

  /**
   * 关闭创建对话框
   */
  private closeCreateDialog(): void {
    if (this.createDialogController) {
      this.createDialogController.close();
      this.createDialogController = null;
    }
  }

  /**
   * 关闭编辑对话框
   */
  private closeEditDialog(): void {
    if (this.editDialogController) {
      this.editDialogController.close();
      this.editDialogController = null;
    }
    this.editingGroup = null;
  }

  /**
   * 关闭删除对话框
   */
  private closeDeleteDialog(): void {
    if (this.deleteDialogController) {
      this.deleteDialogController.close();
      this.deleteDialogController = null;
    }
    this.deletingGroup = null;
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
        
        Text('分组管理')
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor('#333333')
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
        
        Button() {
          Image($r('app.media.icon'))
            .width(20)
            .height(20)
            .fillColor('#007AFF')
        }
        .width(40)
        .height(40)
        .backgroundColor('transparent')
        .onClick(() => this.showCreateGroupDialog())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#FFFFFF')

      // 搜索框
      Row() {
        Image($r('app.media.icon'))
          .width(16)
          .height(16)
          .fillColor('#999999')
          .margin({ left: 12, right: 8 })
        
        TextInput({ placeholder: '搜索分组...', text: this.searchText })
          .layoutWeight(1)
          .backgroundColor('transparent')
          .border({ width: 0 })
          .fontSize(16)
          .fontColor('#333333')
          .onChange((value: string) => this.onSearchTextChange(value))
        
        if (this.searchText) {
          Button() {
            Image($r('app.media.icon'))
              .width(16)
              .height(16)
              .fillColor('#999999')
          }
          .width(32)
          .height(32)
          .backgroundColor('transparent')
          .margin({ right: 8 })
          .onClick(() => this.onSearchTextChange(''))
        }
      }
      .width('100%')
      .height(44)
      .backgroundColor('#F8F8F8')
      .borderRadius(22)
      .margin({ left: 16, right: 16, top: 12, bottom: 12 })

      // 分组列表
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
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.filteredGroups.length === 0) {
        // 空状态
        Column() {
          Image($r('app.media.icon'))
            .width(80)
            .height(80)
            .fillColor('#E5E5E5')
            .margin({ bottom: 16 })
          
          Text(this.searchText ? '未找到相关分组' : '暂无分组')
            .fontSize(16)
            .fontColor('#999999')
            .margin({ bottom: 8 })
          
          if (!this.searchText) {
            Text('点击右上角 + 创建新分组')
              .fontSize(14)
              .fontColor('#CCCCCC')
          }
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        // 分组列表
        List({ space: 0 }) {
          ForEach(this.filteredGroups, (group: AudioGroup, index: number) => {
            ListItem() {
              Row() {
                // 分组图标
                Column() {
                  Image($r('app.media.icon'))
                    .width(24)
                    .height(24)
                    .fillColor('#007AFF')
                }
                .width(48)
                .height(48)
                .backgroundColor('#F0F8FF')
                .borderRadius(24)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .margin({ right: 12 })
                
                // 分组信息
                Column() {
                  Row() {
                    Text(group.groupName)
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor('#333333')
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                      .layoutWeight(1)
                    
                    Text(`${group.audioCount}个音频`)
                      .fontSize(12)
                      .fontColor('#999999')
                      .margin({ left: 8 })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  
                  Text(`包含 ${group.audioCount} 条录音`)
                    .fontSize(14)
                    .fontColor('#666666')
                    .margin({ top: 4 })
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  
                  Text(this.formatDate(group.createTime))
                    .fontSize(12)
                    .fontColor('#999999')
                    .margin({ top: 4 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                
                // 操作按钮
                Row() {
                  Button() {
                    Image($r('app.media.icon'))
                      .width(16)
                      .height(16)
                      .fillColor('#666666')
                  }
                  .width(32)
                  .height(32)
                  .backgroundColor('transparent')
                  .onClick(() => this.showEditGroupDialog(group))
                  
                  Button() {
                    Image($r('app.media.icon'))
                      .width(16)
                      .height(16)
                      .fillColor('#FF3B30')
                  }
                  .width(32)
                  .height(32)
                  .backgroundColor('transparent')
                  .margin({ left: 8 })
                  .onClick(() => this.showDeleteConfirmDialog(group))
                }
                .margin({ left: 12 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor('#FFFFFF')
              .onClick(() => this.viewGroupDetail(group))
            }
            .swipeAction({ end: this.SwipeActionBuilder(group) })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#F8F8F8')
        .divider({
          strokeWidth: 0.5,
          color: '#E5E5E5',
          startMargin: 76,
          endMargin: 16
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  // 滑动操作构建器
  @Builder
  SwipeActionBuilder(group: AudioGroup): void {
    Row() {
      Button('编辑')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#007AFF')
        .width(60)
        .height('100%')
        .onClick(() => this.showEditGroupDialog(group))
      
      Button('删除')
        .fontSize(14)
        .fontColor('#FFFFFF')
        .backgroundColor('#FF3B30')
        .width(60)
        .height('100%')
        .onClick(() => this.showDeleteConfirmDialog(group))
    }
  }
}

// 创建分组对话框
@CustomDialog
struct CreateGroupDialog {
  @State groupName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: (name: string) => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('创建分组')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 20 })
      
      TextInput({ placeholder: '请输入分组名称', text: this.groupName })
        .width('100%')
        .height(44)
        .backgroundColor('#F8F8F8')
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.groupName = value;
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
        
        Button('创建')
          .fontSize(16)
          .fontColor('#FFFFFF')
          .backgroundColor('#007AFF')
          .borderRadius(8)
          .width(100)
          .height(40)
          .onClick(() => {
            if (this.onConfirm) {
              this.onConfirm(this.groupName);
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

// 编辑分组对话框
@CustomDialog
struct EditGroupDialog {
  @State groupName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: (name: string) => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('编辑分组')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 20 })
      
      TextInput({ placeholder: '请输入分组名称', text: this.groupName })
        .width('100%')
        .height(44)
        .backgroundColor('#F8F8F8')
        .borderRadius(8)
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 20 })
        .onChange((value: string) => {
          this.groupName = value;
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
              this.onConfirm(this.groupName);
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

// 删除确认对话框
@CustomDialog
struct DeleteConfirmDialog {
  groupName: string = '';
  controller: CustomDialogController = new CustomDialogController({builder: () => {}});
  onConfirm?: () => void;
  onCancel?: () => void;

  build() {
    Column() {
      Text('删除分组')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#333333')
        .margin({ bottom: 16 })
      
      Text(`确定要删除分组"${this.groupName}"吗？`)
        .fontSize(16)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .margin({ bottom: 8 })
      
      Text('删除后分组内的音频将移至未分组')
        .fontSize(14)
        .fontColor('#999999')
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