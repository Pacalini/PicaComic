part of pica_reader;

extension ToolBar on ComicReadingPage {
  bool get isReversed => appdata.settings[9] == "2" || appdata.settings[9] == "6";

  ///构建底部工具栏
  Widget buildBottomToolBar(
      ComicReadingPageLogic logic, BuildContext context, bool showEps) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        builder: (logic) {
          var text = "E${logic.order} : P${logic.index}";
          if (logic.order == 0) {
            text = "P${logic.index}";
          }

          Widget child = SizedBox(
            height: 105 + MediaQuery.of(context).padding.bottom,
            child: Column(
              children: [
                const SizedBox(
                  height: 8,
                ),
                Row(
                  children: [
                    const SizedBox(
                      width: 8,
                    ),
                    IconButton.filledTonal(
                        onPressed: () => !isReversed
                            ? logic.jumpToLastChapter()
                            : logic.jumpToNextChapter(),
                        icon: const Icon(Icons.first_page)),
                    Expanded(
                      child: buildSlider(logic),
                    ),
                    IconButton.filledTonal(
                        onPressed: () => !isReversed
                            ? logic.jumpToNextChapter()
                            : logic.jumpToLastChapter(),
                        icon: const Icon(Icons.last_page)),
                    const SizedBox(
                      width: 8,
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                    ),
                    GestureDetector(
                      onTap: () => _showPageJumpDialog(context, logic),
                      child: Container(
                        height: 24,
                        padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(text),
                      ),
                    ),
                    const Spacer(),
                    if (App.isWindows)
                      Tooltip(
                        message: "${"全屏".tl}(F12)",
                        child: IconButton(
                          icon: const Icon(Icons.fullscreen),
                          onPressed: () {
                            logic.fullscreen();
                          },
                        ),
                      ),
                    if (App.isAndroid && appdata.settings[76] == "0")
                      Tooltip(
                        message: "屏幕方向".tl,
                        child: IconButton(
                          icon: () {
                            if (logic.rotation == null) {
                              return const Icon(Icons.screen_rotation_alt);
                            } else if (logic.rotation == false) {
                              return const Icon(Icons.screen_lock_portrait);
                            } else {
                              return const Icon(Icons.screen_lock_landscape);
                            }
                          }.call(),
                          onPressed: () {
                            if (logic.rotation == null) {
                              logic.rotation = false;
                              logic.update();
                              SystemChrome.setPreferredOrientations([
                                DeviceOrientation.portraitUp,
                                DeviceOrientation.portraitDown,
                              ]);
                            } else if (logic.rotation == false) {
                              logic.rotation = true;
                              logic.update();
                              SystemChrome.setPreferredOrientations([
                                DeviceOrientation.landscapeLeft,
                                DeviceOrientation.landscapeRight
                              ]);
                            } else {
                              logic.rotation = null;
                              logic.update();
                              SystemChrome.setPreferredOrientations(
                                  DeviceOrientation.values);
                            }
                          },
                        ),
                      ),
                    Tooltip(
                      message: "收藏图片".tl,
                      child: IconButton(
                        icon: const Icon(Icons.favorite_outline),
                        onPressed: () async {
                          try {
                            final id =
                                "${logic.data.sourceKey}-${logic.data.id}";
                            var image = await _persistentCurrentImage();
                            if (image != null) {
                              image = image.split("/").last;
                              var otherInfo = <String, dynamic>{};
                              if (logic.data.type == ReadingType.ehentai) {
                                otherInfo["gallery"] =
                                    (logic.data as EhReadingData)
                                        .gallery
                                        .toJson();
                              } else if (logic.data.type ==
                                  ReadingType.hitomi) {
                                otherInfo["hitomi"] =
                                    (readingData as HitomiReadingData)
                                        .images
                                        .map((e) => e.toMap())
                                        .toList();
                                otherInfo["galleryId"] = readingData.id;
                              } else if (logic.data.type == ReadingType.jm) {
                                otherInfo["jmEpNames"] =
                                    readingData.eps!.values.toList();
                                otherInfo["epsId"] = readingData.eps!.keys
                                    .elementAt(logic.order - 1);
                                otherInfo["bookId"] = readingData.id;
                              }
                              if (logic.data.type != ComicType.other) {
                                otherInfo["eps"] =
                                    readingData.eps?.keys.toList() ?? [];
                              } else {
                                otherInfo["eps"] = readingData.eps;
                              }
                              otherInfo["url"] = logic.urls[logic.index - 1];
                              var favorite = ImageFavorite(
                                  id,
                                  image,
                                  readingData.title,
                                  logic.order,
                                  logic.index,
                                  otherInfo);
                              if (!ImageFavoriteManager.exist(id, logic.order, logic.index)) {
                                ImageFavoriteManager.add(favorite);
                                showToast(message: "已添加至图片收藏".tl);
                              } else {
                                ImageFavoriteManager.delete(favorite);
                                showToast(message: "已取消图片收藏".tl);
                              }
                            }
                          } catch (e) {
                            showToast(message: e.toString());
                          }
                        },
                      ),
                    ),
                    Tooltip(
                      message: "自动翻页".tl,
                      child: IconButton(
                        icon: logic.runningAutoPageTurning
                            ? const Icon(Icons.timer)
                            : const Icon(Icons.timer_sharp),
                        onPressed: () {
                          logic.runningAutoPageTurning =
                              !logic.runningAutoPageTurning;
                          logic.update();
                          logic.autoPageTurning();
                        },
                      ),
                    ),
                    if (showEps)
                      Tooltip(
                        message: "章节".tl,
                        child: IconButton(
                          icon: const Icon(Icons.format_list_numbered),
                          onPressed: openEpsDrawer,
                        ),
                      ),
                    Tooltip(
                      message: "保存图片".tl,
                      child: IconButton(
                        icon: const Icon(Icons.save_alt),
                        onPressed: saveCurrentImage,
                      ),
                    ),
                    Tooltip(
                      message: "分享".tl,
                      child: IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: share,
                      ),
                    ),
                    const SizedBox(
                      width: 5,
                    )
                  ],
                )
              ],
            ),
          );

          child = Material(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
            elevation: 3,
            child: child,
          );

          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            reverseDuration: const Duration(milliseconds: 150),
            switchInCurve: Curves.fastOutSlowIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              var tween = Tween<Offset>(
                  begin: const Offset(0, 1), end: const Offset(0, 0));
              return SlideTransition(
                position: tween.animate(animation),
                child: child,
              );
            },
            child: logic.tools
                ? child
                : const SizedBox(
                    width: 0,
                    height: 0,
                  ),
          );
        },
      ),
    );
  }

  Widget buildSlider(ComicReadingPageLogic logic) {
    if (logic.tools &&
        logic.index != 0 &&
        logic.index != logic.urls.length + 1) {
      return CustomSlider(
        value: logic.index.toDouble(),
        min: 1,
        reversed: isReversed,
        max: logic.urls.length.toDouble(),
        divisions: logic.urls.length - 1,
        onChanged: (i) {
          if (logic.readingMethod == ReadingMethod.topToBottomContinuously) {
            logic.jumpToPage(i.toInt());
            logic.index = i.toInt();
            logic.update();
          } else {
            logic.index = i.toInt();
            logic.jumpToPage(i.toInt());
            logic.update();
          }
        },
      );
    } else {
      return const SizedBox(
        height: 0,
      );
    }
  }

  Iterable<Widget> buildButtons(
      ComicReadingPageLogic logic, BuildContext context) sync* {
    if (context.width > context.height &&
        appdata.appSettings.showButtonsInReader) {
      if (appdata.settings[9] != "4" &&
          logic.readingMethod != ReadingMethod.topToBottom) {
        yield Positioned(
          left: 12,
          top: MediaQuery.of(context).size.height / 2 - 25,
          child: Button.icon(
            icon: const Icon(Icons.keyboard_arrow_left),
            onPressed: () {
              if (appdata.appSettings.flipPageWithClick) {
                return;
              }
              switch (logic.readingMethod) {
                case ReadingMethod.rightToLeft:
                case ReadingMethod.twoPageReversed:
                  logic.jumpToNextPage();
                default:
                  logic.jumpToLastPage();
              }
            },
            size: 24,
          ),
        );
      }
      if (appdata.settings[9] != "4" &&
          logic.readingMethod != ReadingMethod.topToBottom) {
        yield Positioned(
          right: 12,
          top: MediaQuery.of(context).size.height / 2 - 25,
          child: Button.icon(
            icon: const Icon(Icons.keyboard_arrow_right),
            onPressed: () {
              if (appdata.settings[0] == "1") {
                return;
              }
              switch (logic.readingMethod) {
                case ReadingMethod.rightToLeft:
                case ReadingMethod.twoPageReversed:
                  logic.jumpToLastPage();
                default:
                  logic.jumpToNextPage();
              }
            },
            size: 24,
          ),
        );
      }
      yield Positioned(
        left: 4,
        top: 4 + MediaQuery.of(context).padding.top,
        child: IconButton(
          iconSize: 24,
          icon: const Icon(Icons.close),
          onPressed: () => App.globalBack(),
        ),
      );
    }
  }

  ///构建顶部工具栏
  Widget buildTopToolBar(
      ComicReadingPageLogic comicReadingPageLogic, BuildContext context) {
    return Positioned(
      top: 0,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        builder: (logic) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          reverseDuration: const Duration(milliseconds: 150),
          switchInCurve: Curves.fastOutSlowIn,
          child: comicReadingPageLogic.tools
              ? Material(
                  surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
                  elevation: 3,
                  shadowColor:
                      Theme.of(context).colorScheme.shadow.withOpacity(0.3),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                          child: Tooltip(
                            message: "返回".tl,
                            child: IconButton(
                              iconSize: 25,
                              icon: const Icon(Icons.arrow_back_outlined),
                              onPressed: () => App.globalBack(),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 50,
                            constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width - 75),
                            child: Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                readingData.title,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 20),
                              ),
                            ),
                          ),
                        ),
                        //const Spacer(),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                          child: Tooltip(
                            message: "阅读设置".tl,
                            child: IconButton(
                              iconSize: 25,
                              icon: const Icon(Icons.settings),
                              onPressed: () => showSettings(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).paddingTop(MediaQuery.of(context).padding.top),
                )
              : const SizedBox(
                  width: 0,
                  height: 0,
                ),
          transitionBuilder: (Widget child, Animation<double> animation) {
            var tween = Tween<Offset>(
                begin: const Offset(0, -1), end: const Offset(0, 0));
            return SlideTransition(
              position: tween.animate(animation),
              child: child,
            );
          },
        ),
      ),
    );
  }

  ///显示当前的章节和页面位置
  Widget buildPageInfoText(
      ComicReadingPageLogic comicReadingPageLogic, BuildContext context) {
    return Positioned(
      bottom: 13,
      left: 25,
      child: StateBuilder<ComicReadingPageLogic>(
        id: "ToolBar",
        builder: (logic) {
          var epName = readingData.eps?.values
                  .elementAtOrNull(comicReadingPageLogic.order - 1) ??
              "E1";
          if (epName.length > 8) {
            epName = "${epName.substring(0, 8)}...";
          }
          var text = readingData.hasEp
              ? "$epName : ${comicReadingPageLogic.index}/${comicReadingPageLogic.urls.length}"
              : "${comicReadingPageLogic.index}/${comicReadingPageLogic.urls.length}";
          return GestureDetector(
            onTap: () => _showPageJumpDialog(context, logic),
            child: Stack(
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 1.4
                      ..color = (useDarkBackground ||
                              Theme.of(context).brightness == Brightness.dark)
                          ? Colors.black
                          : Colors.white,
                  ),
                ),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 14,
                    color: useDarkBackground ? Colors.white : null,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPageJumpDialog(BuildContext context, ComicReadingPageLogic logic) {
    final maxPage = logic.urls.length;
    if (maxPage <= 0) {
      showToast(message: "没有可跳转的页面".tl);
      return;
    }
    final controller = TextEditingController(text: logic.index.toString());
    String? errorText;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text("跳转到页".tl),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "请输入 @min-@max 之间的页数"
                        .tlParams({"min": "1", "max": maxPage.toString()}),
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    autofocus: true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
                    ],
                    decoration: InputDecoration(
                      hintText: "页数".tl,
                      errorText: errorText,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (value) {
                      final err = _validatePageInput(value, maxPage);
                      if (err != null) {
                        setState(() => errorText = err);
                      } else {
                        final page = int.parse(value);
                        Navigator.pop(dialogContext);
                        logic.jumpToPage(page, true);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text("取消".tl),
                ),
                TextButton(
                  onPressed: () {
                    final err = _validatePageInput(controller.text, maxPage);
                    if (err != null) {
                      setState(() => errorText = err);
                    } else {
                      final page = int.parse(controller.text);
                      Navigator.pop(dialogContext);
                      logic.jumpToPage(page, true);
                    }
                  },
                  child: Text("确认".tl),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _validatePageInput(String value, int maxPage) {
    if (value.isEmpty) {
      return "请输入页数".tl;
    }
    final page = int.tryParse(value);
    if (page == null) {
      return "请输入有效的数字".tl;
    }
    if (page < 1 || page > maxPage) {
      return "页数超出范围 (@min-@max)"
          .tlParams({"min": "1", "max": maxPage.toString()});
    }
    return null;
  }
}
