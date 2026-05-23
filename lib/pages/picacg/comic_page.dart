import 'package:flutter/material.dart';
import 'package:pica_comic/comic_source/built_in/picacg.dart';
import 'package:pica_comic/components/select_download_eps.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/picacg_network/methods.dart';
import 'package:pica_comic/foundation/ui_mode.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/category_comics_page.dart';
import 'package:pica_comic/pages/picacg/comments_page.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/components/components.dart';
import '../../network/picacg_network/picacg_download_model.dart';
import '../comic_page.dart';

class PicacgComicPage extends BaseComicPage<ComicItem> {
  @override
  final String id;

  @override
  final String? cover;

  const PicacgComicPage(this.id, this.cover, {super.key});

  @override
  ActionFunc? get onLike => () {
        network.likeOrUnlikeComic(id);
        data!.isLiked = !data!.isLiked;
        update();
      };

  @override
  String? get likeCount => data?.likes.toString();

  @override
  bool get isLiked => data!.isLiked;
  
  @override
  Future<ComicItem?> loadLocalData() async {
    String title = '', cover = '', subTitle = '';
    bool found = false;
    final h = pageHistory;
    if (h != null && h.title.isNotEmpty) {
      title = h.title; cover = h.cover; subTitle = h.subtitle; found = true;
    }
    if (!found) {
      try {
        final dlId = DownloadManager().generateId(sourceKey, id);
        if (DownloadManager().isExists(dlId)) {
          final dl = await DownloadManager().getComicOrNull(dlId);
          if (dl != null && dl.name.isNotEmpty) {
            title = dl.name; subTitle = dl.subTitle;
            cover = 'file://${DownloadManager().path}/${DownloadManager().getDirectory(dlId)}/cover.jpg';
            found = true;
          }
        }
      } catch (_) {}
    }
    if (!found) {
      try {
        final folders = await LocalFavoritesManager().find(id, const FavoriteType(0));
        if (folders.isNotEmpty) {
          final item = LocalFavoritesManager().getComic(folders.first, id, const FavoriteType(0));
          title = item.name; subTitle = item.author; cover = item.coverPath; found = true;
        }
      } catch (_) {}
    }
    if (!found) return null;
    try {
      return ComicItem.fromJson({
        "creator": {"id": "", "title": "", "email": "", "name": "",
                     "level": 0, "exp": 0, "avatarUrl": "",
                     "frameUrl": null, "isPunched": null, "slogan": null},
        "id": id, "title": title, "thumbUrl": cover,
        "description": "", "author": subTitle, "chineseTeam": "",
        "categories": <String>[], "tags": <String>[],
        "likes": 0, "comments": 0, "isLiked": false, "isFavourite": false,
        "epsCount": 0, "time": "0000-00-00 00:00:00", "pagesCount": 0
      });
    } catch (_) { return null; }
  }

  
  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: picacg.isLogin,
      needLoadFolderData: false,
      folders: const {"Picacg": "Picacg"},
      initialFolder: data!.isFavourite ? null : "Picacg",
      favoriteOnPlatform: data!.isFavourite,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      cancelPlatformFavorite: () async {
        var res = await network.favouriteOrUnfavouriteComic(id);
        if(res) {
          data!.isFavourite = false;
          return const Res(true);
        }
        return Res.error("网络错误".tl);
      },
      selectFolderCallback: (name, p) async {
        if (p == 0) {
          var res = await network.favouriteOrUnfavouriteComic(id);
          if(res) {
            data!.isFavourite = true;
            update();
            return const Res(true);
          } else {
            return Res.error("网络错误".tl);
          }
        } else {
          LocalFavoritesManager().addComic(name, toLocalFavoriteItem());
          return const Res(true);
        }
      },
    ));
  }

  @override
  ActionFunc? get openComments => () => showComments(App.globalContext!, id);

  @override
  String? get commentsCount => data!.comments.toString();

  @override
  void download() {
    _downloadComic(data!, App.globalContext!, data!.eps);
  }

  @override
  EpsData? get eps {
    return EpsData(
      data!.eps,
      (i) async {
        await History.findOrCreate(data!);
        App.globalTo(
            () => ComicReadingPage.picacg(id, i + 1, data!.eps, data!.title));
      },
    );
  }

  @override
  String? get introduction => data?.description;

  @override
  Future<Res<ComicItem>> loadData() => network.getComicInfo(id);

  @override
  int? get pages => data?.pagesCount;

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(
      () => ComicReadingPage.picacg(
        id,
        history!.ep,
        data!.eps,
        data!.title,
        initialPage: history.page,
      ),
    );
  }

  @override
  Widget recommendationBuilder(data) =>
      SliverGridComics(comics: data.recommendation, sourceKey: sourceKey);

  @override
  String get tag => "Picacg Comic Page $id";

  @override
  Map<String, List<String>>? get tags => {
        "作者".tl: data!.author.toList(),
        "汉化".tl: data!.chineseTeam.toList(),
        "分类".tl: data!.categories,
        "标签".tl: data!.tags
      };

  @override
  void tapOnTag(String tag, String key) {
    if (data!.categories.contains(tag)) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          categoryKey: "picacg",
        ),
      );
    } else if (data!.author == tag) {
      context.to(
        () => CategoryComicsPage(
          category: tag,
          param: "a",
          categoryKey: "picacg",
        ),
      );
    } else {
      context.to(
        () => SearchResultPage(
          keyword: tag,
          sourceKey: sourceKey,
        ),
      );
    }
  }

  @override
  ThumbnailsData? get thumbnailsCreator => null;

  @override
  String? get title => data?.title;

  @override
  Future<bool> loadFavorite(ComicItem data) async {
    return data.isFavourite ||
        (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem())).isNotEmpty;
  }

  @override
  Card? get uploaderInfo => Card(
        elevation: 0,
        color: context.colorScheme.inversePrimary,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              Expanded(
                flex: 0,
                child: Avatar(
                  size: 50,
                  avatarUrl: data!.creator.avatarUrl,
                  frame: data!.creator.frameUrl,
                  couldBeShown: true,
                  name: data!.creator.name,
                  slogan: data!.creator.slogan,
                  level: data!.creator.level,
                ),
              ),
              Expanded(
                flex: 3,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 10, 0, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data!.creator.name,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      Text(
                          "${data!.time.substring(0, 10)} ${data!.time.substring(11, 19)}更新")
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  String get source => "Picacg";

  @override
  FavoriteItem toLocalFavoriteItem() => FavoriteItem(
        target: id,
        name: data!.title,
        coverPath: data!.thumbUrl,
        author: data!.author,
        type: FavoriteType.picacg,
        tags: data!.tags,
      );

  @override
  String get downloadedId => id;

  @override
  String get sourceKey => "picacg";
}

void _downloadComic(
    ComicItem comic, BuildContext context, List<String> eps) async {
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }
  var downloaded = <int>[];
  if (DownloadManager().isExists(comic.id)) {
    var downloadedComic = (await DownloadManager().getComicOrNull(comic.id))!
      as DownloadedComic;
    downloaded.addAll(downloadedComic.downloadedEps);
  }
  var content = SelectDownloadChapter(
    eps,
    (selectedEps) {
      downloadManager.addPicDownload(comic, selectedEps);
      App.globalBack();
      showToast(message: "已加入下载队列".tl);
    },
    downloaded,
  );
  if (UiMode.m1(App.globalContext!)) {
    showModalBottomSheet(
      context: App.globalContext!,
      builder: (context) => content,
    );
  } else {
    showSideBar(
      App.globalContext!,
      content,
      useSurfaceTintColor: true,
    );
  }
}
