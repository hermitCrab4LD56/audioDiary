import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AudioRecord, AudioGroup, TabType, SearchResult } from '../model/DataModel';
import { DatabaseService } from '../service/DatabaseService';
import { common } from '@kit.AbilityKit';
import { router } from '@kit.ArkUI';

const DOMAIN = 0x0000;

@Entry
@Component
struct Index {
  @State currentTab: TabType = TabType.ALL;
  @State audioRecords: AudioRecord[] = [];
  @State audioGroups: AudioGroup[] = [];
  @State searchKeyword: string = '';
  @State isSearchMode: boolean = false;
  @State searchResults: SearchResult[] = [];
  @State isLoading: boolean = true;
  
  private databaseService = DatabaseService.getInstance();
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  async aboutToAppear(): Promise<void> {
    hilog.info(DOMAIN, 'Index', 'Page aboutToAppear');
    await this.initializeData();
    this.loginWithHuaweiID();
  }

  /**
   * 初始化数据
   */
  private async initializeData(): Promise<void> {
    try {
      this.isLoading = true;
      await this.databaseService.initDatabase(this.context);
      await this.loadAudioRecords();
      await this.loadAudioGroups();
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
    try {
      this.audioRecords = await this.databaseService.queryAllAudioRecords();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to load audio records: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 加载音频分组
   */
  private async loadAudioGroups(): Promise<void> {
    try {
      this.audioGroups = await this.databaseService.queryAllGroups();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to load audio groups: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 搜索音频
   */
  private async searchAudio(keyword: string): Promise<void> {
    if (!keyword.trim()) {
      this.isSearchMode = false;
      this.searchResults = [];
      return;
    }

    try {
      this.isSearchMode = true;
      const records = await this.databaseService.searchAudioRecords(keyword);
      this.searchResults = records.map(record => {
        const searchResult: SearchResult = {
          type: 'audio',
          data: record,
          matchText: record.fileName
        };
        return searchResult;
      });
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to search audio: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 切换Tab
   */
  private onTabChange(tabType: TabType): void {
    this.currentTab = tabType;
    this.isSearchMode = false;
    this.searchKeyword = '';
  }

  /**
   * 获取当前显示的音频列表
   */
  private getCurrentAudioList(): AudioRecord[] {
    if (this.isSearchMode) {
      return this.searchResults
        .filter(result => result.type === 'audio')
        .map(result => result.data);
    }

    switch (this.currentTab) {
      case TabType.ALL:
        return this.audioRecords;
      case TabType.RECORD:
        return this.audioRecords.filter(record => record.isTop);
      case TabType.GROUP:
        return this.audioRecords.filter(record => record.groupId && record.groupId !== 1);
      default:
        return this.audioRecords;
    }
  }

  /**
   * 跳转到录音页面
   */
  private navigateToRecord(): void {
    router.pushUrl({
      url: 'pages/RecordPage'
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'Index', `Failed to navigate to record page: ${JSON.stringify(error)}`);
    });
  }

  /**
   * 跳转到分组页面
   */
  private navigateToGroup(): void {
    router.pushUrl({
      url: 'pages/GroupPage'
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'Index', `Failed to navigate to group page: ${JSON.stringify(error)}`);
    });
  }

  /**
   * 跳转到音频详情页面
   */
  private navigateToAudioDetail(audioRecord: AudioRecord): void {
    router.pushUrl({
      url: 'pages/AudioDetailPage',
      params: {
        audioRecord: audioRecord
      }
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'Index', `Failed to navigate to audio detail page: ${JSON.stringify(error)}`);
    });
  }

  /**
   * 切换置顶状态
   */
  private async toggleTopStatus(audioRecord: AudioRecord): Promise<void> {
    try {
      await this.databaseService.toggleTopStatus(audioRecord.id, !audioRecord.isTop);
      await this.loadAudioRecords();
    } catch (error) {
      hilog.error(DOMAIN, 'Index', `Failed to toggle top status: ${JSON.stringify(error)}`);
    }
  }

  /**
   * 格式化时长
   */
  private formatDuration(duration: number): string {
    const seconds = Math.floor(duration / 1000);
    const minutes = Math.floor(seconds / 60);
    const remainingSeconds = seconds % 60;
    return `${minutes.toString().padStart(2, '0')}:${remainingSeconds.toString().padStart(2, '0')}`;
  }

  /**
   * 格式化文件大小
   */
  private formatFileSize(size: number): string {
    if (size < 1024) {
      return `${size}B`;
    } else if (size < 1024 * 1024) {
      return `${(size / 1024).toFixed(1)}KB`;
    } else {
      return `${(size / (1024 * 1024)).toFixed(1)}MB`;
    }
  }

  /**
   * 格式化创建时间
   */
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
    Column() {
      // 顶部标题栏
      Row() {
        Text('音频日记')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
        
        Blank()
        
        // 分组按钮
        Button() {
          Image($r('app.media.icon'))
            .width(20)
            .height(20)
            .fillColor('#666666')
        }
        .width(40)
        .height(40)
        .backgroundColor('#F5F5F5')
        .borderRadius(20)
        .onClick(() => this.navigateToGroup())
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
          .margin({ right: 8 })
        
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
          Button('全部')
            .fontSize(14)
            .fontColor(this.currentTab === TabType.ALL ? '#007AFF' : '#666666')
            .backgroundColor('transparent')
            .border({ width: 0 })
            .onClick(() => this.onTabChange(TabType.ALL))
          
          Button('置顶')
            .fontSize(14)
            .fontColor(this.currentTab === TabType.RECORD ? '#007AFF' : '#666666')
            .backgroundColor('transparent')
            .border({ width: 0 })
            .margin({ left: 24 })
            .onClick(() => this.onTabChange(TabType.RECORD))
          
          Button('分组')
            .fontSize(14)
            .fontColor(this.currentTab === TabType.GROUP ? '#007AFF' : '#666666')
            .backgroundColor('transparent')
            .border({ width: 0 })
            .margin({ left: 24 })
            .onClick(() => this.onTabChange(TabType.GROUP))
          
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
              this.AudioRecordItem(audioRecord)
            }
            .swipeAction({ end: this.SwipeActions(audioRecord) })
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

      // 底部录音按钮
      Row() {
        Button() {
          Image($r('app.media.icon'))
            .width(24)
            .height(24)
            .fillColor('#FFFFFF')
        }
        .width(60)
        .height(60)
        .backgroundColor('#007AFF')
        .borderRadius(30)
        .onClick(() => this.navigateToRecord())
      }
      .width('100%')
      .height(80)
      .justifyContent(FlexAlign.Center)
      .backgroundColor('#FFFFFF')
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F8F8F8')
  }

  @Builder
  AudioRecordItem(audioRecord: AudioRecord) {
    Row() {
      // 播放按钮
      Button() {
        Image($r('app.media.icon'))
          .width(20)
          .height(20)
          .fillColor('#007AFF')
      }
      .width(40)
      .height(40)
      .backgroundColor('#E3F2FD')
      .borderRadius(20)
      .margin({ right: 12 })
      .onClick(() => this.navigateToAudioDetail(audioRecord))

      // 音频信息
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
    .onClick(() => this.navigateToAudioDetail(audioRecord))
  }

  @Builder
  SwipeActions(audioRecord: AudioRecord) {
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

  /**
   * Sample code for using HUAWEI ID to log in to atomic service.
   * According to the Atomic Service Review Guide, when a atomic service has an account system,
   * the option to log in with a HUAWEI ID must be provided.
   * The following presets the atomic service to use the HUAWEI ID silent login function.
   * To enable the atomic service to log in successfully using the HUAWEI ID, please refer
   * to the HarmonyOS HUAWEI ID Access Guide to configure the client ID and fingerprint certificate.
   */
  private loginWithHuaweiID() {
    // Create a login request and set parameters
    const loginRequest = new authentication.HuaweiIDProvider().createLoginWithHuaweiIDRequest();
    // Whether to forcibly launch the HUAWEI ID login page when the user is not logged in with the HUAWEI ID
    loginRequest.forceLogin = false;
    // Execute login request
    const controller = new authentication.AuthenticationController();
    controller.executeRequest(loginRequest).then((data: authentication.LoginWithHuaweiIDResponse) => {
      const loginWithHuaweiIDResponse = data;
      const authCode = loginWithHuaweiIDResponse.data?.authorizationCode;
      // Send authCode to the backend in exchange for unionID, session

    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', 'error: %{public}s', JSON.stringify(error));
      if (error.code === authentication.AuthenticationErrorCode.ACCOUNT_NOT_LOGGED_IN) {
        // HUAWEI ID is not logged in, it is recommended to jump to the login guide page

      }
    });
  }
}