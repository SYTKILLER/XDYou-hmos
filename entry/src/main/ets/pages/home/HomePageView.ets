import { hdsMaterial, HdsTabs } from '@kit.UIDesignKit';
import { SymbolGlyphModifier } from '@kit.ArkUI';
import { HomeTab } from './HomeTab';
import { AllFeaturesTab } from './AllFeaturesTab';
import { SettingTab } from '../setting/SettingTab';
import { GlobalTimerController } from '../../controller/GlobalTimerController';
import { HomepageController } from '../../controller/HomepageController';
import { Log } from '../../utils/Log';

/**
 * 登录后主框架：官方 UIDesignKit 的 HdsTabs 三页签（首页 / 全部功能 / 设置）。
 * 沉浸光感悬浮页签（官方 API）：barOverlap(true) 页签叠加内容，
 * barFloatingStyle.systemMaterialEffect 用 hdsMaterial ADAPTIVE 自适应材质（@since 6.1.0(23)）。
 * 页签图标为 HarmonyOS Symbol：TabBarSymbol normal/selected 双 SymbolGlyphModifier（@since 12）。
 * 进入框架即启动整分定时器并静默全量刷新（对应 Dart HomePageMaster refreshAtStart）。
 */
@Component
export struct HomePageView {
  // 主题响应式 token（AppTheme.syncStorage 维护），页签选中图标颜色随种子色/深浅色刷新。
  @StorageProp('themePrimary') themePrimary: string = '#0A59F7';
  @State currentIndex: number = 0;

  aboutToAppear(): void {
    GlobalTimerController.start();
    HomepageController.refreshAll().catch((e: Object): void => {
      Log.warn(`homepage silent refresh failed: ${e}`);
    });
  }

  private tabSymbol(normalIcon: Resource, selectedIcon: Resource): TabBarSymbol {
    return {
      normal: new SymbolGlyphModifier(normalIcon).fontColor([$r('app.color.text_secondary')]),
      selected: new SymbolGlyphModifier(selectedIcon).fontColor([this.themePrimary])
    };
  }

  build() {
    Column() {
      HdsTabs() {
        TabContent() {
          HomeTab()
        }
        .tabBar(new BottomTabBarStyle(this.tabSymbol($r('sys.symbol.house'), $r('sys.symbol.house_fill')),
          $r('app.string.tab_home')))

        TabContent() {
          AllFeaturesTab()
        }
        .tabBar(new BottomTabBarStyle(this.tabSymbol($r('sys.symbol.square_grid_2x2'), $r('sys.symbol.square_grid_2x2')),
          $r('app.string.tab_features')))

        TabContent() {
          SettingTab()
        }
        .tabBar(new BottomTabBarStyle(this.tabSymbol($r('sys.symbol.gearshape'), $r('sys.symbol.gearshape_fill')),
          $r('app.string.tab_settings')))
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .vertical(false)
      .barFloatingStyle({
        barWidth: { smallWidth: 260, mediumWidth: 320, largeWidth: 380 },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      .width('100%')
      .height('100%')
    }
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_bg'))
  }
}
