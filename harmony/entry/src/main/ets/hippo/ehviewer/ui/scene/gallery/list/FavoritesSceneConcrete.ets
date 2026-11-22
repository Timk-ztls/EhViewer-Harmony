/*
 * U-02b：`FavoritesScene` 的薄子类。默认注入 `UnavailableLocalFavorites`（warn 兜底）。
 */
import { FavoritesScene } from './FavoritesScene';
import { UnavailableLocalFavorites } from './FavoritesScene';

export class FavoritesSceneConcrete extends FavoritesScene {
  constructor() {
    super();
    this.setLocalFavoritesRepo(new UnavailableLocalFavorites());
  }

  getSceneName(): string {
    return 'FavoritesScene';
  }
}
