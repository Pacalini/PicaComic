import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:html/dom.dart';
import 'package:pica_comic/base.dart';
import 'package:pica_comic/foundation/app.dart';
import 'package:pica_comic/foundation/log.dart';
import 'package:pica_comic/network/cloudflare.dart';
import 'package:pica_comic/network/cookie_jar.dart';
import 'package:pica_comic/network/nhentai_network/tags.dart';
import 'package:pica_comic/network/res.dart';
import 'package:pica_comic/tools/extensions.dart';
import 'package:pica_comic/tools/time.dart';
import 'package:pica_comic/tools/translations.dart';
import 'package:pica_comic/pages/pre_search_page.dart';
import '../app_dio.dart';
import 'models.dart';
import 'package:html/parser.dart';

export 'models.dart';

class NhentaiNetwork {
  factory NhentaiNetwork() => _cache ?? (_cache = NhentaiNetwork._create());

  NhentaiNetwork._create();

  static NhentaiNetwork? _cache;

  SingleInstanceCookieJar? cookieJar;

  bool logged = false;

  String baseUrl = "https://nhentai.net";

  late Dio dio;

  Future<void> init() async {
    cookieJar = SingleInstanceCookieJar.instance;
    for (var cookie in cookieJar!.loadForRequest(Uri.parse(baseUrl))) {
      if (cookie.name == "sessionid") {
        logged = true;
      }
    }
    dio = logDio(BaseOptions(
      headers: {
        "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Accept-Language": "zh-CN,zh-TW;q=0.9,zh;q=0.8,en-US;q=0.7,en;q=0.6",
        "Referer": "$baseUrl/",
      },
      validateStatus: (i) => i == 200 || i == 302,
    ));
    dio.interceptors.add(CookieManagerSql(cookieJar!));
    dio.interceptors.add(CloudflareInterceptor());
  }

  void logout() async {
    logged = false;
    cookieJar!.delete(Uri.parse(baseUrl), "sessionid");
  }

  Future<Res<String>> get(String url) async {
    if (cookieJar == null) {
      await init();
    }
    try {
      var res = await dio.get<String>(url, options: Options(followRedirects: false));
      if (res.statusCode == 302) {
        var path = res.headers["Location"]?.first ??
            res.headers["location"]?.first ??
            "";
        return get(Uri.parse(url).replace(path: path).toString());
      }
      return Res(res.data);
    } catch (e) {
      return Res(null, errorMessage: e.toString());
    }
  }

  Future<Res<String>> post(String url, dynamic data,
      [Map<String, String>? headers]) async {
    if (cookieJar == null) {
      await init();
    }
    try {
      var res = await dio.post<String>(url, data: data, options: Options(headers: headers));
      return Res(res.data);
    } catch (e) {
      return Res(null, errorMessage: e.toString());
    }
  }

  NhentaiComicBrief parseComic(Element comicDom) {
    var img = comicDom.querySelector("a > img")!.attributes["data-src"]!;
    img = "https:$img";
    var name = comicDom.querySelector("div.caption")!.text;
    var id = comicDom.querySelector("a")!.attributes["href"]!.nums;
    var lang = "Unknown";
    var tags = comicDom.attributes["data-tags"] ?? "";
    if (tags.contains("12227")) {
      lang = "English";
    } else if (tags.contains("6346")) {
      lang = "日本語";
    } else if (tags.contains("29963")) {
      lang = "中文";
    }
    var tagsRes = <String>[];
    for (var tag in tags.split(" ")) {
      if (nhentaiTags[tag] != null) {
        tagsRes.add(nhentaiTags[tag]!);
      }
    }
    return NhentaiComicBrief(name, img, id, lang, tagsRes);
  }

  List<T> removeNullValue<T extends Object>(List<T?> list) {
    while (list.remove(null)) {}
    return List.from(list);
  }

  Future<Res<NhentaiHomePageData>> getHomePage([int? page]) async {
    var url = baseUrl;
    if (page != null && page != 1) {
      url = "$url?page=$page";
    }
    var res = await get(url);
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);
      List<Element> popularDoms;
      if (url == baseUrl) {
        popularDoms = document.querySelectorAll(
            "div.container.index-container.index-popular > div.gallery");
      } else {
        popularDoms = const [];
      }
      var latest = document
          .querySelectorAll("div.container.index-container > div.gallery");

      return Res(NhentaiHomePageData(
        removeNullValue(List.generate(
            popularDoms.length, (index) => parseComic(popularDoms[index]))),
        removeNullValue(List.generate(latest.length - popularDoms.length,
            (index) => parseComic(latest[index + popularDoms.length]))),
      ));
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<bool>> loadMoreHomePageData(NhentaiHomePageData data) async {
    var res = await get("$baseUrl?page=${data.page + 1}");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);

      var latest = document.querySelectorAll("div.gallery");

      data.latest.addAll(removeNullValue(
          List.generate(latest.length, (index) => parseComic(latest[index]))));

      data.page++;

      return const Res(true);
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<List<NhentaiComicBrief>>> search(String keyword, int page,
      [NhentaiSort sort = NhentaiSort.recent]) async {
    if (appdata.searchHistory.contains(keyword)) {
      appdata.searchHistory.remove(keyword);
    }
    appdata.searchHistory.add(keyword);
    appdata.writeHistory();
    var res = await get(
        "$baseUrl/search/?q=${Uri.encodeComponent(keyword)}&page=$page${sort.value}");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);

      var comicDoms = document.querySelectorAll("div.gallery");

      var results = document.querySelector("div#content > h1")!.text;

      Future.microtask(() {
        try {
          StateController.find<PreSearchController>().update();
        } catch (e) {
          //
        }
      });

      if (comicDoms.isEmpty) {
        return const Res([], subData: 0);
      }

      return Res(
          removeNullValue(List.generate(
              comicDoms.length, (index) => parseComic(comicDoms[index]))),
          subData: (int.parse(results.nums) / comicDoms.length).ceil());
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<NhentaiComic>> getComicInfo(String id) async {
    Res<String> res;
    if (id == "") {
      res = await get("$baseUrl/random/");
      if (res.error) {
        return Res.fromErrorRes(res);
      }
    } else {
      res = await get("$baseUrl/g/$id/");
    }
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      String combineSpans(Element? title) {
        var res = "";
        for (var span in title?.children ?? []) {
          res += span.text;
        }
        return res;
      }

      var document = parse(res.data);
      
      id = id == "" ? document.querySelector("h3#gallery_id")!.text.nums : id;

      var cover = document
          .querySelector("div#cover > a > img")!
          .attributes["data-src"]!;
      cover = "https:$cover";

      var title = combineSpans(document.querySelector("h1.title")!);

      var subTitle = combineSpans(document.querySelector("h2.title"));

      Map<String, List<String>> tags = {};
      for (var field in document.querySelectorAll("div.tag-container")) {
        var fieldName =
            field.firstChild!.text!.removeAllBlank.replaceLast(":", "");
        if (fieldName == "Uploaded") {
          var timeStr = document.querySelector("time")?.attributes["datetime"];
          if (timeStr != null) {
            tags["时间".tl] = [timeToString(DateTime.parse(timeStr))];
            continue;
          }
        }
        tags[fieldName] = [];
        for (var span in field.querySelectorAll("span.name")) {
          tags[fieldName]!.add(span.text);
        }
      }

      bool favorite =
          document.querySelector("button#favorite > span.text")?.text !=
                  "Favorite" &&
              logged;

      var thumbnails = <String>[];
      for (var t in document.querySelectorAll("a.gallerythumb > img")) {
        thumbnails.add("https:${t.attributes["data-src"]!}");
      }

      var recommendations = <NhentaiComicBrief>[];
      for (var comic in document.querySelectorAll("div.gallery")) {
        var c = parseComic(comic);
        recommendations.add(c);
      }
      String token = "";
      try {
        var script = document
            .querySelectorAll("script")
            .firstWhere((element) => element.text.contains("csrf_token"))
            .text;
        token = script.split("csrf_token: \"")[1].split("\",")[0];
      } catch (e) {
        // ignore
      }

      return Res(NhentaiComic(id, title, subTitle, cover, tags, favorite,
          thumbnails, recommendations, token));
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<List<NhentaiComment>>> getComments(String id) async {
    var res = await get("$baseUrl/api/gallery/$id/comments");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var json = const JsonDecoder().convert(res.data);
      var comments = <NhentaiComment>[];
      for (var c in json) {
        comments.add(NhentaiComment(
            c["poster"]["username"],
            "https://i3.nhentai.net/${c["poster"]["avatar_url"]}",
            c["body"],
            c["post_date"]));
      }
      return Res(comments);
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<List<String>>> getImages(String id) async {
    var res = await get("$baseUrl/g/$id/1/");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);
      var scripts = document
          .querySelectorAll("script");
      var script0 = scripts
          .firstWhere((element) => element.text.contains("window._n_app"))
          .text;
      var script1 = scripts
          .firstWhere((element) => element.text.contains("window._gallery"))
          .text;

      Map<String, dynamic> parseJavaScriptJson(String jsCode) {
        String jsonText = jsCode.split('JSON.parse("')[1].split('");')[0];
        String decodedJsonText =
            jsonText.replaceAll("\\u0022", "\"").replaceAll("\\u005C", "\\");

        return json.decode(decodedJsonText);
      }

      var galleryData = parseJavaScriptJson(script1);

      String mediaServer = script0.split("image_cdn_urls: [\"")[1].split('"')[0];
      String mediaId = galleryData["media_id"];

      var images = <String>[];

      for (var image in galleryData["images"]["pages"]) {
        var extension = switch (image["t"]) {
          "j" => "jpg",
          "p" => "png",
          "g" => "gif",
          "w" => "webp",
          _ => "jpg"
        };
        images.add(
            "https://$mediaServer/galleries/$mediaId/${images.length + 1}"
            ".$extension");
      }
      return Res(images);
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  // 一页 25 个
  Future<Res<List<NhentaiComicBrief>>> getFavorites(int page) async {
    if (!logged) {
      return const Res(null, errorMessage: "login required");
    }
    var res = await get("$baseUrl/favorites/?page=$page");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);
      var comics = document.querySelectorAll("div.gallery");
      var lastPagination = document
          .querySelector("section.pagination > a.last")
          ?.attributes["href"]
          ?.nums;
      return Res(
          removeNullValue(List.generate(
              comics.length, (index) => parseComic(comics[index]))),
          subData: lastPagination == null ? 1 : int.parse(lastPagination));
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }

  Future<Res<bool>> favoriteComic(String id, String token) async {
    var res = await post("$baseUrl/api/gallery/$id/favorite", null, {
      "Referer": "$baseUrl/g/$id",
      "X-Csrftoken": token,
      "X-Requested-With": "XMLHttpRequest"
    });
    if (res.error) {
      return Res.fromErrorRes(res);
    } else {
      return const Res(true);
    }
  }

  Future<Res<bool>> unfavoriteComic(String id, String token) async {
    var res = await post("$baseUrl/api/gallery/$id/unfavorite", null, {
      "Referer": "$baseUrl/g/$id",
      "X-Csrftoken": token,
      "X-Requested-With": "XMLHttpRequest"
    });
    if (res.error) {
      return Res.fromErrorRes(res);
    } else {
      return const Res(true);
    }
  }

  Future<Res<List<NhentaiComicBrief>>> getCategoryComics(
      String path, int page, NhentaiSort sort) async {
    var param = switch (sort) {
      NhentaiSort.recent => '/',
      NhentaiSort.popularToday => '/popular-today',
      NhentaiSort.popularWeek => '/popular-week',
      NhentaiSort.popularMonth => '/popular-month',
      NhentaiSort.popularAll => '/popular'
    };
    var res = await get("$baseUrl$path$param?page=$page");
    if (res.error) {
      return Res.fromErrorRes(res);
    }
    try {
      var document = parse(res.data);

      var comicDoms = document.querySelectorAll("div.gallery");

      var results = document.querySelector("div#content > h1")!.text;

      Future.microtask(() {
        try {
          StateController.find<PreSearchController>().update();
        } catch (e) {
          //
        }
      });

      if (comicDoms.isEmpty) {
        return const Res([], subData: 0);
      }

      return Res(
          removeNullValue(List.generate(
              comicDoms.length, (index) => parseComic(comicDoms[index]))),
          subData: (int.parse(results.nums) / comicDoms.length).ceil());
    } catch (e, s) {
      LogManager.addLog(LogLevel.error, "Data Analyse", "$e\n$s");
      return Res(null, errorMessage: "Failed to Parse Data: $e");
    }
  }
}

enum NhentaiSort {
  recent(""),
  popularToday("&sort=popular-today"),
  popularWeek("&sort=popular-week"),
  popularMonth("&sort=popular-month"),
  popularAll("&sort=popular");

  final String value;

  const NhentaiSort(this.value);

  static NhentaiSort fromValue(String value) {
    switch (value) {
      case "":
        return NhentaiSort.recent;
      case "&sort=popular-today":
        return NhentaiSort.popularToday;
      case "&sort=popular-week":
        return NhentaiSort.popularWeek;
      case "&sort=popular-month":
        return NhentaiSort.popularMonth;
      case "&sort=popular":
        return NhentaiSort.popularAll;
      default:
        return NhentaiSort.recent;
    }
  }
}
