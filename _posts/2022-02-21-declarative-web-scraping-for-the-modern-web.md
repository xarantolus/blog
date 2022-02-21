---
layout: post
title: Declarative scraping for the modern web, or why your scraper breaks all the time
excerpt: "Web scrapers break all the time due to changes to websites. This post shows a method on how to scrape modern sites with higher robustness."
---

There are certain command-line tools we all use a lot. Whether it's the GNU core utilities for quickly getting info about files, FFmpeg to convert between different image formats or [`youtube-dl`](https://github.com/ytdl-org/youtube-dl) to just download that small sound effect without having to find yet another free downloading site.

However, not all of theses tools are the same. How often have you updated the GNU core utils to try a new feature? Likely never. I have only updated FFmpeg intentionally like *once*, and that was when I came across a `webp` file for the first time. `youtube-dl` however? Very often.

That's because the sites supported by it change all the time. The maintainers play the cat-and-mouse game and update the tool to fix yet another scraper that broke and prevented people from downloading yet another batch of sound effects. 

The answer to why this happens is likely obvious to most readers, but stay with me for a different approach.

### How web scraping works
Most web-scraper work very similar: they download an HTML page, parse it into a tree of elements and then run queries on that parsed tree.
They define stuff like "I want the inner text of the `span` with the class `price`", or "get the attribute `src` of the first `video` tag". These are all fine things, but they are prone to breaking. If a CSS class is renamed or an element is moved somewhere else, the scraper breaks and needs to be fixed.

It's even worse when programs need to extract JSON data from within a page. A [regex like the following](https://github.com/ytdl-org/youtube-dl/blob/34722270741fb9c06f978861c1e5f503291070d8/youtube_dl/extractor/youtube.py#L285) works, but is also really prone to breaking:

```python
_YT_INITIAL_DATA_RE = r'(?:window\s*\[\s*["\']ytInitialData["\']\s*\]|ytInitialData)\s*=\s*({.+?})\s*;'
```

And after that regex was used to extract data, there's still the problem that sites like YouTube deliver a *very* nested JSON document with at least a dozen levels of depth.

So in general, I think it is fair to say that imperatively describing how to get data from the page works fine *for a while*, but starts to break on most small changes, requiring updates.


#### SQL
Let's talk about SQL for a bit. Yes, it has almost nothing to do with web scraping, but it has some nice properties I think we *should have* in web scraping.

The difference between SQL and most other languages we programmers use is that SQL is declarative. This means that we don't tell the database system what it should do do get the data, we just tell it *what kind of data* we want. We define properties and conditions the result must have. The database management system must find a way to satisfy our query *somehow*. As users of database systems we don't need to know or care whether the `where` condition was executed as an Index-Join, Hash-Join or a nested loop. We just get the data.

In web scraping we use the usual, imperative way of describing how to get different variables from the page. Sometimes we even programmatically navigate a browser just because the site is rendered exclusively using JavaScript.

I think we should do web scraping differently, a bit more like SQL.


### A declarative approach
Now let's think about how we could bring a more declarative approach to web scraping.

Modern web sites that use JavaScript for rendering their content often come with a rather large snippet of JSON data in their payload that describes what kind of page should actually be shown. We could now do the naive approach of extracting the JavaScript variable using a regex, but we also know that this is prone to breaking in the future. 

Another problematic thing about this is the structure of the JSON data itself: if you want to get elements that are nested 20 levels deep, there are 20 different chances of something being renamed and breaking your scraper.

**So here are basically the key points a declarative approach should solve**:
1. **Stop relying on data location** (e.g. "the object after `var x = {...}`")
2. **Reduce dependency on internal data naming** (e.g. the keys within the extracted JSON data)

And if we think about it, it actually sounds pretty easy: just write a program that finds any (largeish) JSON object in a page and then iterate over all levels in it to find what we are looking for (e.g. all objects with a `title` and `videoId` key).

If the tool is able to find *any* object in a page, we also don't need to care about the position of the data anymore. And if we only rely on a minimal set of attributes the objects we're looking for should have, then we don't need to care if someone changes the structure of everything else.


Enter `jsonx`, a tool that does just that. If you have the Go toolchain installed, you can just install it from source using the following command. Alternatively, there's binaries for Linux and Windows [here](https://github.com/xarantolus/blog/releases/tag/jsonx).

```sh
go install github.com/xarantolus/jsonextract/cmd/jsonx@latest
```

Now we can just tell the tool to get all objects that have a `videoId`, `title`, and ` channelId` from a page (I also added [`jq`](https://stedolan.github.io/jq/) for nicer formatting of the output):

```sh
$ jsonx "https://www.youtube.com/watch?v=-Oox2w5sMcA" videoId title channelId | jq
{
  "videoId": "-Oox2w5sMcA",
  "title": "Starship Animation",
  "lengthSeconds": "310",
  "channelId": "UCtI0Hodo5o5dUb67FeUjDeA",
  "isOwnerViewing": false,
  "shortDescription": "",
  "isCrawlable": true,
  "thumbnail": {
    "thumbnails": [
      {
        "url": "https://i.ytimg.com/vi/-Oox2w5sMcA/hqdefault.jpg?sqp=-oaymwEiCKgBEF5IWvKriqkDFQgBFQAAAAAYASUAAMhCPQCAokN4AQ==&rs=AOn4CLDqv77rSQ83UV-8s5rWMX8iInJcgQ",
        "width": 168,
        "height": 94
      },
      {
        "url": "https://i.ytimg.com/vi/-Oox2w5sMcA/hqdefault.jpg?sqp=-oaymwEiCMQBEG5IWvKriqkDFQgBFQAAAAAYASUAAMhCPQCAokN4AQ==&rs=AOn4CLAizx8wyIv50KOlkMRQnj8WAAgJ1w",
        "width": 196,
        "height": 110
      },
      {
        "url": "https://i.ytimg.com/vi/-Oox2w5sMcA/hqdefault.jpg?sqp=-oaymwEjCPYBEIoBSFryq4qpAxUIARUAAAAAGAElAADIQj0AgKJDeAE=&rs=AOn4CLBL7HeKYvEL8u3Glg0SLPGGZNgtSg",
        "width": 246,
        "height": 138
      },
      {
        "url": "https://i.ytimg.com/vi/-Oox2w5sMcA/hqdefault.jpg?sqp=-oaymwEjCNACELwBSFryq4qpAxUIARUAAAAAGAElAADIQj0AgKJDeAE=&rs=AOn4CLDsOBxYvamnjSZZPKkIx87_JttNIQ",
        "width": 336,
        "height": 188
      },
      {
        "url": "https://i.ytimg.com/vi/-Oox2w5sMcA/maxresdefault.jpg",
        "width": 1920,
        "height": 1080
      }
    ]
  },
  "allowRatings": true,
  "viewCount": "1421951",
  "author": "SpaceX",
  "isPrivate": false,
  "isUnpluggedCorpus": false,
  "isLiveContent": false
}
```

So isn't that just nice? We just said "I want all objects with these three attributes from this page" and it just worked. No need to look into the full structure of the page or data. We just describe what we want and the tool figures out the rest. 

Obviously it relies on some object in the JSON tree having these three attributes, but compared to different approaches this is a **very minimal dependency**. So this approach now "just works", is simpler to use and is arguably less prone to breaking.


#### Drawbacks
As with any approach, this one also has its disadvantages.

First of all, it does not work with all web pages, as most pages deliver their content mostly using HTML. Pages with JSON are somewhat rare, but if the data is there, it will be easy.

The second drawback is that not all data in JavaScript snippets of pages is actually valid JSON. Just add a `NaN` somewhere and it's no longer valid JSON, which would break the scraper. The `jsonx` tool works around this by using [a JavaScript lexer](https://github.com/tdewolff/parse/) to directly transform some invalid tokens to valid JSON (e.g. `NaN` just becomes `null`). So `jsonx` is very liberal in what it accepts, reminding of the [robustness principle](https://en.wikipedia.org/wiki/Robustness_principle).

The third drawback is somewhat implementation-specific: if you feed thousands of opening braces `[` into the tool, it gets noticeably slow. That's because as soon as it doesn't find a matching bracket or the content between the two brackets is invalid JSON, it needs to go back to the first bracket and continue from there, possibly doing the same thing over and over (so this *can* become somewhat of an <code>O(n<sup>2</sup>)</code> complexity if I'm not mistaken). This doesn't happen much in *real* pages, but a website looking to fight scrapers could use this implementation weakness.


### What I want you to do
If you build a tool or app that could use this approach, you should definitely try to implement the data extraction part that just looks at everything in a page starting with `[` or `{` in search for validish JSON data. 

Also not relying on the data structure is very important. Feel free to implement logic in a programming language of your choice that parses JSON and dynamically finds only objects with certain keys, no matter the nesting. It's actually pretty simple, you just need to do a case distinction between arrays (-> recursively iterate all objects in them), objects (-> check if they have all required keys) and primitive data types (ignore).

And if you like the approach, you should implement it in your scraper! This makes the software we use every day more robust, which is a goal we should strive for.


### Conclusion
If you found this interesting, feel free to comment by opening an issue on my [blog repository](https://github.com/xarantolus/blog) or send me an e-mail. 

If you're interested in low-level Android stuff, you can [read my post about the Linux multitouch protocol on Android](2021-05-18-how-to-tap-the-android-screen-from-the-underlying-linux-system.md). Alternatively if you've heard of or have a KNX "smart home" system, you might be interested in [this other post about my KNX setup](2021-08-26-programmatically-interact-with-a-KNX-smart-home-system.md).


---------

#### Side note
This is not a rant about `youtube-dl`. In fact, I'm a big fan and thankful that people take the time to maintain it. The examples are used to illustrate what we programmers *usually* do because *it works* and are not meant to point fingers.
