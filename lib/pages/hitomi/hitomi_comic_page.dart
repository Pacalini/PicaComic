import 'package:flutter/material.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/components/components.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/history.dart';
import 'package:pica_comic/foundation/local_favorites.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/download.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_main_network.dart';
import 'package:pica_comic/network/hitomi_network/hitomi_models.dart';
import 'package:pica_comic/network/hitomi_network/image.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/pages/comic_page.dart';
import 'package:pica_comic/pages/hitomi/hitomi_search.dart';
import 'package:pica_comic/pages/reader/comic_reading_page.dart';
import 'package:pica_comic/pages/search_result_page.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/translations.dart';

class HitomiComicPage extends BaseComicPage<HitomiComic> {
  HitomiComicPage(HitomiComicBrief comic, {super.key})
      : link = comic.link,
        comicCover = comic.cover;

  const HitomiComicPage.fromLink(this.link, {super.key, String? cover})
      : comicCover = cover;

  final String link;

  final String? comicCover;

  @override
  String? get url => link;

  @override
  void openFavoritePanel() {
    favoriteComic(FavoriteComicWidget(
      havePlatformFavorite: false,
      needLoadFolderData: false,
      localFavoriteItem: toLocalFavoriteItem(),
      setFavorite: (b) {
        if (favorite != b) {
          favorite = b;
          update();
        }
      },
      selectFolderCallback: (folder, page) {
        LocalFavoritesManager().addComic(
          folder,
          FavoriteItem.fromHitomi(data!.toBrief(link, cover!)),
        );
        return Future.value(const Res(true));
      },
    ));
  }

  @override
  String? get cover => data?.cover ?? comicCover;

  @override
  void download() => _downloadComic(data!, context, cover!, link);

  @override
  EpsData? get eps => null;

  @override
  String? get introduction => null;

  @override
  Future<Res<HitomiComic>> loadData() async {
    return HiNetwork().getComicInfo(link);
  }

  @override
  int? get pages => null;

  @override
  void read(History? history) async {
    history = await History.createIfNull(history, data!);
    App.globalTo(
      () => ComicReadingPage.hitomi(
        data!,
        link,
        initialPage: history!.page,
      ),
    );
  }

  @override
  Widget? recommendationBuilder(HitomiComic data) => SliverGrid(
        delegate: SliverChildBuilderDelegate(childCount: data.related.length,
            (context, i) {
          return HitomiComicTileDynamicLoading(data.related[i]);
        }),
        gridDelegate: SliverGridDelegateWithComics(),
      );

  @override
  String get tag => "Hitomi ComicPage $link";

  @override
  Map<String, List<String>>? get tags => {
        "Artists": data!.artists ?? ["N/A"],
        "Groups": data!.group,
        "Categories": data!.type.toList(),
        "Time": data!.time.toList(),
        "Languages": data!.lang.toList(),
        "Tags":
            List.generate(data!.tags.length, (index) => data!.tags[index].name),
        "Series": data!.parodys != null
            ? List.generate(data!.parodys!.length, (index) => data!.parodys![index].name)
            : [],
        "Characters": data!.characters != null
            ? List.generate(data!.characters!.length, (index) => data!.characters![index].name)
            : [],
      };

  @override
  bool get enableTranslationToCN => App.locale.languageCode == "zh";

  @override
  void tapOnTag(String tag, String key) {
    if (key == "Tags") {
      if (tag.endsWith(' ♀')) {
        tag = "female:${tag.replaceLast(" ♀", "")}";
      } else if (tag.endsWith('♂')) {
        tag = "male:${tag.replaceLast(" ♂", "")}";
      } else {
        tag = "tag:$tag";
      }
    }
    if (tag.contains(" ")) {
      tag = tag.replaceAll(' ', '_');
    }
    String? categoryParam = switch (key) {
      "Artists" => "artist:$tag",
      "Groups" => "group:$tag",
      "Categories" => "type:$tag",
      "Languages" => "language:$tag",
      "Series" => "series:$tag",
      "Characters" => "character:$tag",
      "Tags" => tag,
      "Time" => null,
      _ => null
    };
    if (categoryParam != null && tag != "N/A") {
      context.to(
            () => SearchResultPage(
          keyword: categoryParam,
          sourceKey: 'hitomi',
        ),
      );
    }
  }

  @override
  Map<String, String> get headers =>
      {"User-Agent": webUA, "Referer": "https://hitomi.la/"};

  @override
  ThumbnailsData? get thumbnailsCreator => ThumbnailsData([], (page) async {
        try {
          var gg = GG();
          var images = <String>[];
          for (var file in data!.files) {
            images.add(await gg.urlFromUrlFromHash(
                data!.id, file, "webpsmallsmalltn", "webp"));
          }
          return Res(images);
        } catch (e, s) {
          LogManager.addLog(LogLevel.error, "Network", "$e\n$s");
          return Res(null, errorMessage: e.toString());
        }
      }, 2);

  @override
  void onThumbnailTapped(int index) async {
    await History.findOrCreate(data!, page: index + 1);
    App.globalTo(() => ComicReadingPage.hitomi(
          data!,
          link,
          initialPage: index + 1,
        ));
  }

  @override
  String? get title => data?.title;

  @override
  Card? get uploaderInfo => null;

  @override
  Future<bool> loadFavorite(HitomiComic data) async {
    return (await LocalFavoritesManager().findWithModel(toLocalFavoriteItem()))
        .isNotEmpty;
  }

  @override
  String get id => data!.id;

  @override
  String get source => "hitomi";

  @override
  FavoriteItem toLocalFavoriteItem() =>
      FavoriteItem.fromHitomi(data!.toBrief(link, cover!));

  @override
  String get downloadedId => "hitomi${data!.id}";

  @override
  String get sourceKey => "hitomi";
}

void _downloadComic(
    HitomiComic comic, BuildContext context, String cover, String link) {
  if (downloadManager.isExists(comic.id)) {
    showToast(message: "已下载".tl);
    return;
  }
  for (var i in downloadManager.downloading) {
    if (i.id == comic.id) {
      showToast(message: "下载中".tl);
      return;
    }
  }
  downloadManager.addHitomiDownload(comic, cover, link);
  showToast(message: "已加入下载队列".tl);
}
