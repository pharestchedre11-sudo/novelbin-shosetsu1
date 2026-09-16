-- {"id":26091601,"ver":"2026.1.0","libVer":"1.0.0","author":"OpenAI","dep":["url>=1.0.0"]}
-- NovelBin 2026
-- Source: https://novelbin.com
-- Shosetsu extension using the current NovelBin-style HTML/AJAX structure.
-- If NovelBin changes its HTML again, the CSS selectors below can be adjusted.

local qs = Require("url").querystring

local defaults = {
    baseURL = "https://novelbin.xyz",
    hasCloudFlare = false,
    hasSearch = true,
    chapterType = ChapterType.HTML,

    hot = "/sort/hot-novel",
    latest = "/sort/latest-novel",
    completed = "/sort/novel-completed",

    function text(v)
        return v and v:text() or ""
    end,

    function absolute(self, url)
        if not url or url == "" then return url end
        if url:match("^https?://") then return url end
        if url:sub(1,1) ~= "/" then url = "/" .. url end
        return self.baseURL .. url
    end,

    function shrinkURL(self, url)
        if not url then return url end
        return url:gsub("^" .. self.baseURL:gsub("(%p)", "%%%1") .. "/", "")
    end,

    function imageURL(self, img)
        if not img then return nil end
        local src = img:attr("src")
        if not src or src == "" then src = img:attr("data-src") end
        if not src or src == "" then src = img:attr("data-cfsrc") end
        return self:absolute(src)
    end,

    function parseList(self, document)
        local items = document:select(
            ".list-cat2 .item," ..
            ".archive .list .row," ..
            ".ul-list1.ul-list1-2.ss-custom .li-row"
        )

        return map(items, function(v)
            local link = v:selectFirst(
                "a[href*='/novel/']," ..
                ".novel-title a," ..
                ".truyen-title a," ..
                ".tit a," ..
                "a"
            )

            if not link then return nil end

            local titleEl = v:selectFirst(
                ".title h3," ..
                ".novel-title," ..
                ".truyen-title," ..
                ".tit," ..
                "h3"
            )

            local img = v:selectFirst("img")
            local title = titleEl and titleEl:text() or link:text()

            if not title or title == "" then return nil end

            return Novel {
                title = title,
                link = self:shrinkURL(link:attr("href")),
                imageURL = self:imageURL(img)
            }
        end)
    end,

    function search(self, data)
        local query = data[QUERY]
        local page = data[PAGE] or 1

        local url = qs({
            keyword = query,
            page = page
        }, self.baseURL .. "/search")

        return self:parseList(GETDocument(url))
    end,

    function hotList(self, data)
        local page = data[PAGE] or 1
        return self:parseList(
            GETDocument(self.baseURL .. self.hot .. "?page=" .. page)
        )
    end,

    function latestList(self, data)
        local page = data[PAGE] or 1
        return self:parseList(
            GETDocument(self.baseURL .. self.latest .. "?page=" .. page)
        )
    end,

    function completedList(self, data)
        local page = data[PAGE] or 1
        return self:parseList(
            GETDocument(self.baseURL .. self.completed .. "?page=" .. page)
        )
    end,

    function parseChapterElement(self, el, order)
        local href = el:attr("href")
        if not href or href == "" then
            href = el:attr("value")
        end
        if not href or href == "" then return nil end

        local title = el:attr("title")
        if not title or title == "" then title = el:text() end

        if not title or title == "" then return nil end

        return NovelChapter {
            title = title,
            link = self:shrinkURL(href),
            order = order
        }
    end,

    function parseChapterDocument(self, doc)
        local links = doc:select("li[data-chapter-item] a")
        if links:isEmpty() then
            links = doc:select(".list-chapter li a")
        end
        if links:isEmpty() then
            links = doc:select(".m-newest2 .ul-list5 li a")
        end
        if links:isEmpty() then
            links = doc:select("select option")
        end

        local chapters = {}
        local order = 0

        for i = 0, links:size() - 1 do
            local c = self:parseChapterElement(links:get(i), order)
            if c then
                chapters[#chapters + 1] = c
                order = order + 1
            end
        end

        return chapters
    end,

    function parseNovel(self, url, loadChapters)
        local doc = GETDocument(self:absolute(url))

        local titleEl = doc:selectFirst("h1.title, .m-desc > .tit, .title")
        if not titleEl then
            error("NovelBin: novel not found")
        end

        local title = titleEl:text()

        local img = doc:selectFirst(
            "div.book img," ..
            ".m-imgtxt img," ..
            "img.cover"
        )

        local descEl = doc:selectFirst(".desc-text, .txt > .inner")
        local description = descEl and descEl:text() or ""

        local authors = {}
        local authorEls = doc:select(
            ".info a[href*='/author/']," ..
            ".txt a[href*='/author/']"
        )
        for i = 0, authorEls:size() - 1 do
            authors[#authors + 1] = authorEls:get(i):text()
        end

        local genres = {}
        local genreEls = doc:select(
            ".info a[href*='/genre/']," ..
            ".txt a[href*='/genre/']"
        )
        for i = 0, genreEls:size() - 1 do
            genres[#genres + 1] = genreEls:get(i):text()
        end

        local statusEl = doc:selectFirst(
            ".info .text-primary," ..
            ".info a[href*='/status/']," ..
            ".txt span[title='Status'] + div.right span.s1"
        )

        local statusText = statusEl and statusEl:text() or ""
        local status = NovelStatus.UNKNOWN
        if statusText:lower():find("completed") then
            status = NovelStatus.COMPLETED
        elseif statusText ~= "" then
            status = NovelStatus.PUBLISHING
        end

        local info = NovelInfo {
            title = title,
            authors = authors,
            genres = genres,
            status = status,
            description = description,
            imageURL = self:imageURL(img)
        }

        if loadChapters then
            local chapters = {}

            -- Current NovelBin-style pages commonly expose a novel ID for
            -- the AJAX chapter archive.
            local idEl = doc:selectFirst("[data-novel-id]")
            local novelId = idEl and idEl:attr("data-novel-id") or nil

            if novelId and novelId ~= "" then
                local ajaxURL = qs({
                    novelId = novelId
                }, self.baseURL .. "/ajax-chapter-option")

                local ok, ajaxDoc = pcall(GETDocument, ajaxURL)
                if ok and ajaxDoc then
                    chapters = self:parseChapterDocument(ajaxDoc)
                end
            end

            -- Fallback: chapter links embedded in the novel page.
            if #chapters == 0 then
                chapters = self:parseChapterDocument(doc)
            end

            info:setChapters(AsList(chapters))
        end

        return info
    end,

    function getPassage(self, url)
        local doc = GETDocument(self:absolute(url))

        local titleEl = doc:selectFirst(
            ".chapter-text," ..
            ".chr-title," ..
            ".chapter-title," ..
            ".wp > .top > span"
        )

        local chapter = doc:selectFirst(
            "#chr-content," ..
            "#chapter-content," ..
            ".chapter-content," ..
            ".wp > .txt"
        )

        if not chapter then
            error("NovelBin: chapter content not found")
        end

        -- Remove common advertising / navigation elements.
        chapter:select("script"):remove()
        chapter:select("iframe"):remove()
        chapter:select("ins"):remove()
        chapter:select(".ads"):remove()
        chapter:select(".adsbygoogle"):remove()
        chapter:select("noscript"):remove()

        if titleEl then
            local title = titleEl:text()
            if title and title ~= "" then
                chapter:child(0):before("\n# " .. title .. "\n")
            end
        end

        return pageOfElem(chapter)
    end
}

local function novelData(baseURL, self)
    self = setmetatable(self or {}, {
        __index = function(_, k)
            local d = defaults[k]
            if type(d) == "function" then
                return wrap(self, d)
            end
            return d
        end
    })

    self.baseURL = baseURL
    self.listings = {
        Listing("Hot", true, self.hotList),
        Listing("Latest", true, self.latestList),
        Listing("Completed", true, self.completedList)
    }

    return self
end

return novelData("https://novelbin.xyz", {
    id = 26091601,
    name = "NovelBin 2026",
    imageURL = "https://novelbin.com/images/logo.png"
})
