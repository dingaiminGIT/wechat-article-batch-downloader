package officialaccountdownload

import (
	"bytes"
	"crypto/md5"
	"encoding/base64"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"

	htmltomarkdown "github.com/JohannesKaufmann/html-to-markdown"
	"github.com/PuerkitoBio/goquery"
	"golang.org/x/net/html"
)

var md_convert = htmltomarkdown.NewConverter("", true, nil)

type ArticleAuthCredential struct {
	Uin        string
	Key        string
	PassTicket string
	Cookie     string
}

var ArticleAuthProvider func(biz string) ArticleAuthCredential

// WeChat starts returning an interactive verification page when article HTML is
// requested too quickly. Serialize article page requests and keep a small gap;
// images are downloaded separately and are not subject to this gate.
var articleRequestGate = struct {
	sync.Mutex
	next time.Time
}{}

// Export tasks may finish at the same time. Keep the shared corpus index update
// serialized so one task cannot overwrite records written by another task.
var (
	articleIndexMu sync.Mutex
	articleIndexes = make(map[string]*articleJSONLIndex)
)

type articleJSONLIndex struct {
	lines     [][]byte
	positions map[string]int
}

const (
	safeArticleRequestInterval = time.Second
	FastArticleRequestInterval = 500 * time.Millisecond
)

func waitForArticleRequestSlot(interval time.Duration) {
	if interval <= 0 {
		interval = safeArticleRequestInterval
	}
	articleRequestGate.Lock()
	defer articleRequestGate.Unlock()
	if wait := time.Until(articleRequestGate.next); wait > 0 {
		time.Sleep(wait)
	}
	articleRequestGate.next = time.Now().Add(interval)
}

type OfficialAccountDownload struct {
	article    *WechatOfficialArticle
	imageMu    sync.Mutex
	imageCache map[string]cachedImage
	// ArticleRequestInterval defaults to the conservative one-request-per-second
	// pace. The desktop app explicitly opts into the faster 500 ms pace.
	ArticleRequestInterval time.Duration
	OnProgress             func(downloaded int64) // callback after each image download, reports bytes downloaded
}

type cachedImage struct {
	data     []byte
	mimeType string
}

func (c *OfficialAccountDownload) reportProgress(n int64) {
	if c.OnProgress != nil {
		c.OnProgress(n)
	}
}

func (c *OfficialAccountDownload) imageBytes(imgURL string) ([]byte, string, error) {
	// ExportHTML and Markdown use the same images. Cache them for the lifetime
	// of one article so each URL is downloaded only once.
	c.imageMu.Lock()
	defer c.imageMu.Unlock()
	if image, ok := c.imageCache[imgURL]; ok {
		return image.data, image.mimeType, nil
	}
	data, mimeType, err := downloadImageBytes(imgURL)
	if err != nil {
		return nil, "", err
	}
	if c.imageCache == nil {
		c.imageCache = make(map[string]cachedImage)
	}
	c.imageCache[imgURL] = cachedImage{data: data, mimeType: mimeType}
	c.reportProgress(int64(len(data)))
	return data, mimeType, nil
}

func (c *OfficialAccountDownload) SaveURLAsMarkdown(url string, dir_path string) error {
	article, err := c.FetchArticle(url)
	if err != nil {
		return err
	}
	return c.ConvertHtmlToMarkdown(article, dir_path)
}

func (c *OfficialAccountDownload) SaveURLAsMarkdownFile(url string, filePath string) error {
	article, err := c.FetchArticle(url)
	if err != nil {
		return err
	}
	return c.ConvertHtmlToMarkdownFile(article, filePath)
}

type ArticleExportRecord struct {
	Title        string `json:"title"`
	Author       string `json:"author"`
	URL          string `json:"url"`
	PublishTime  string `json:"publish_time"`
	Text         string `json:"text"`
	HTMLPath     string `json:"html_path"`
	MarkdownPath string `json:"markdown_path"`
	TextPath     string `json:"text_path"`
}

func (c *OfficialAccountDownload) ExportURL(url string, dirPath string, baseName string, needCompress bool) error {
	article, err := c.FetchArticle(url)
	if err != nil {
		return err
	}
	return c.ExportArticle(article, url, dirPath, baseName, needCompress)
}

func (c *OfficialAccountDownload) ExportArticle(article *WechatOfficialArticle, sourceURL string, dirPath string, baseName string, needCompress bool) error {
	if article == nil {
		return fmt.Errorf("article is nil")
	}
	baseName = cleanExportBaseName(baseName)
	if baseName == "" {
		baseName = cleanExportBaseName(article.Title)
	}
	if baseName == "" {
		baseName = "article"
	}

	htmlDir := filepath.Join(dirPath, "html")
	markdownDir := filepath.Join(dirPath, "markdown")
	textDir := filepath.Join(dirPath, "text")
	for _, dir := range []string{htmlDir, markdownDir, textDir} {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return err
		}
	}

	htmlPath := filepath.Join(htmlDir, baseName+".html")
	markdownPath := filepath.Join(markdownDir, baseName+".md")
	textPath := filepath.Join(textDir, baseName+".txt")

	// Markdown stores local images. Build it first so the self-contained HTML
	// can reuse those same bytes from memory instead of downloading every image
	// a second time.
	if err := c.ConvertHtmlToMarkdownFile(article, markdownPath); err != nil {
		return err
	}
	htmlContent, err := c.BuildHTMLFromArticle(article, needCompress)
	if err != nil {
		return err
	}
	if err := os.WriteFile(htmlPath, []byte(htmlContent), 0644); err != nil {
		return err
	}
	text := articlePlainText(article)
	if err := os.WriteFile(textPath, []byte(text), 0644); err != nil {
		return err
	}

	record := ArticleExportRecord{
		Title:        article.Title,
		Author:       firstNonEmpty(article.Creator, article.AuthorNickname),
		URL:          sourceURL,
		PublishTime:  article.PublishTimeStr,
		Text:         text,
		HTMLPath:     filepath.ToSlash(filepath.Join("html", baseName+".html")),
		MarkdownPath: filepath.ToSlash(filepath.Join("markdown", baseName+".md")),
		TextPath:     filepath.ToSlash(filepath.Join("text", baseName+".txt")),
	}
	stylePath := filepath.Join(dirPath, "style_corpus.jsonl")
	if err := appendArticleJSONL(stylePath, record); err != nil {
		return err
	}
	chownToSudoUser(dirPath, htmlDir, markdownDir, textDir, filepath.Join(markdownDir, "images"), htmlPath, markdownPath, textPath, stylePath)
	return nil
}

func chownToSudoUser(paths ...string) {
	uidStr := os.Getenv("SUDO_UID")
	gidStr := os.Getenv("SUDO_GID")
	if uidStr == "" || gidStr == "" {
		return
	}
	uid, err := strconv.Atoi(uidStr)
	if err != nil {
		return
	}
	gid, err := strconv.Atoi(gidStr)
	if err != nil {
		return
	}
	seen := map[string]bool{}
	for _, target := range paths {
		if target == "" || seen[target] {
			continue
		}
		seen[target] = true
		info, err := os.Stat(target)
		if err != nil {
			continue
		}
		if info.IsDir() && strings.HasSuffix(filepath.ToSlash(target), "/images") {
			_ = filepath.WalkDir(target, func(path string, _ os.DirEntry, err error) error {
				if err == nil {
					_ = os.Chown(path, uid, gid)
				}
				return nil
			})
			continue
		}
		_ = os.Chown(target, uid, gid)
	}
}

func cleanExportBaseName(name string) string {
	for _, ext := range []string{".html", ".md", ".txt"} {
		if strings.HasSuffix(strings.ToLower(name), ext) {
			name = name[:len(name)-len(ext)]
			break
		}
	}
	name = strings.ReplaceAll(name, "/", "_")
	name = strings.ReplaceAll(name, "\\", "_")
	name = strings.TrimSpace(name)
	return name
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}

func articlePlainText(article *WechatOfficialArticle) string {
	doc, err := goquery.NewDocumentFromReader(strings.NewReader(article.Content))
	var text string
	if err == nil {
		doc.Find("script,style").Remove()
		text = doc.Text()
	} else {
		text = article.Content
	}
	lines := strings.Split(text, "\n")
	cleaned := make([]string, 0, len(lines)+4)
	cleaned = append(cleaned, article.Title)
	if article.AuthorNickname != "" || article.PublishTimeStr != "" {
		cleaned = append(cleaned, strings.TrimSpace(article.AuthorNickname+" "+article.PublishTimeStr))
	}
	for _, line := range lines {
		line = strings.Join(strings.Fields(line), " ")
		if line != "" {
			cleaned = append(cleaned, line)
		}
	}
	return strings.TrimSpace(strings.Join(cleaned, "\n\n")) + "\n"
}

func appendArticleJSONL(path string, record ArticleExportRecord) error {
	articleIndexMu.Lock()
	defer articleIndexMu.Unlock()

	index := articleIndexes[path]
	if index == nil {
		index = &articleJSONLIndex{positions: make(map[string]int)}
		if existing, err := os.ReadFile(path); err == nil {
			for _, line := range bytes.Split(existing, []byte{'\n'}) {
				line = bytes.TrimSpace(line)
				if len(line) == 0 {
					continue
				}
				var old ArticleExportRecord
				if err := json.Unmarshal(line, &old); err == nil && old.URL != "" {
					index.positions[old.URL] = len(index.lines)
				}
				index.lines = append(index.lines, append([]byte(nil), line...))
			}
		}
		articleIndexes[path] = index
	}
	line, err := json.Marshal(record)
	if err != nil {
		return err
	}
	if position, exists := index.positions[record.URL]; exists {
		index.lines[position] = line
		return writeArticleJSONL(path, index.lines)
	}

	// New downloads are the common path. Append only the new record instead of
	// decoding and rewriting the entire, steadily growing corpus for every
	// article. Duplicate URLs still use an atomic rewrite above.
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0644)
	if err != nil {
		return err
	}
	lineWithNewline := append(append([]byte(nil), line...), '\n')
	if _, err = file.Write(lineWithNewline); err != nil {
		_ = file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	index.positions[record.URL] = len(index.lines)
	index.lines = append(index.lines, line)
	return nil
}

func writeArticleJSONL(path string, lines [][]byte) error {
	var output []byte
	if len(lines) > 0 {
		output = bytes.Join(lines, []byte{'\n'})
		output = append(output, '\n')
	}
	temporary, err := os.CreateTemp(filepath.Dir(path), ".style_corpus-*.jsonl")
	if err != nil {
		return err
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0644); err != nil {
		_ = temporary.Close()
		return err
	}
	if _, err := temporary.Write(output); err != nil {
		_ = temporary.Close()
		return err
	}
	if err := temporary.Close(); err != nil {
		return err
	}
	return os.Rename(temporaryPath, path)
}

func appendArticleIndex(path string, baseName string, record ArticleExportRecord) error {
	rows := [][]string{{"id", "title", "author", "publish_time", "url", "html", "markdown", "text"}}
	if existing, err := os.Open(path); err == nil {
		reader := csv.NewReader(existing)
		existingRows, readErr := reader.ReadAll()
		_ = existing.Close()
		if readErr == nil {
			for index, row := range existingRows {
				if index == 0 {
					continue
				}
				if len(row) > 4 && row[4] == record.URL {
					continue
				}
				rows = append(rows, row)
			}
		}
	}
	rows = append(rows, []string{
		baseName,
		record.Title,
		record.Author,
		record.PublishTime,
		record.URL,
		record.HTMLPath,
		record.MarkdownPath,
		record.TextPath,
	})
	file, err := os.Create(path)
	if err != nil {
		return err
	}
	defer file.Close()
	writer := csv.NewWriter(file)
	defer writer.Flush()
	return writer.WriteAll(rows)
}

func (c *OfficialAccountDownload) BuildHTMLFromURL(url string, need_compress_img bool) (string, error) {
	article := c.article
	if article == nil {
		r, err := c.FetchArticle(url)
		if err != nil {
			return "", err
		}
		article = r
	}
	return c.BuildHTMLFromArticle(article, need_compress_img)
}

func (c *OfficialAccountDownload) ConvertHtmlToMarkdown(article *WechatOfficialArticle, dir_path string) error {
	filename := strings.ReplaceAll(article.Title, "/", "_")
	filename = strings.ReplaceAll(filename, "\\", "_")
	return c.ConvertHtmlToMarkdownFile(article, filepath.Join(dir_path, filename+".md"))
}

func (c *OfficialAccountDownload) ConvertHtmlToMarkdownFile(article *WechatOfficialArticle, filePath string) error {
	dir_path := filepath.Dir(filePath)
	// Create images directory
	imagesDirName := "images"
	imagesDirPath := filepath.Join(dir_path, imagesDirName)
	if err := os.MkdirAll(imagesDirPath, 0755); err != nil {
		return err
	}

	// Process HTML content to download images and replace links
	doc, err := goquery.NewDocumentFromReader(strings.NewReader(article.Content))
	if err != nil {
		return err
	}

	// Preserve newlines in text nodes by replacing them with a placeholder
	// This is needed because HTML parsers and markdown converters often treat newlines as whitespace
	newlinePlaceholder := "WECHATNEWLINEHOLDER"
	var replaceNewlines func(*html.Node)
	replaceNewlines = func(n *html.Node) {
		if n.Type == html.TextNode {
			if strings.Contains(n.Data, "\n") {
				n.Data = strings.ReplaceAll(n.Data, "\n", newlinePlaceholder)
			}
			return
		}
		for c := n.FirstChild; c != nil; c = c.NextSibling {
			if c.Type == html.ElementNode {
				tag := strings.ToLower(c.Data)
				// Skip pre-formatted blocks where newlines should be preserved naturally
				if tag == "pre" || tag == "code" || tag == "script" || tag == "style" {
					continue
				}
			}
			replaceNewlines(c)
		}
	}

	for _, n := range doc.Nodes {
		replaceNewlines(n)
	}

	doc.Find("mp-common-mpaudio").Each(func(i int, s *goquery.Selection) {
		voiceEncodeFileId := s.AttrOr("voice_encode_fileid", "")
		if voiceEncodeFileId != "" {
			audioURL := "https://res.wx.qq.com/voice/getvoice?mediaid=" + voiceEncodeFileId
			s.AppendHtml(fmt.Sprintf(`<audio src="%s" controls="controls"></audio>`, audioURL))
		}
	})

	doc.Find("iframe.video_iframe").Each(func(i int, s *goquery.Selection) {
		vid := s.AttrOr("data-vid", "")
		if vid == "" {
			vid = s.AttrOr("vid", "")
		}
		if vid == "" {
			vid = s.AttrOr("data-mpvid", "")
		}
		if vid != "" {
			for _, video := range article.Videos {
				if video.VideoID == vid {
					if len(video.MpVideoTransInfo) > 0 {
						videoURL := video.MpVideoTransInfo[0].Url
						cover := s.AttrOr("data-cover", "")
						posterAttr := ""
						if cover != "" {
							if decodedCover, err := url.QueryUnescape(cover); err == nil {
								cover = decodedCover
							}
							posterAttr = fmt.Sprintf(` poster="%s"`, escapeHTML(cover))
						}
						videoHTML := fmt.Sprintf(`<video src="%s"%s controls="controls" style="width: 100%%; height: auto;"></video>`, videoURL, posterAttr)
						s.ReplaceWithHtml(videoHTML)
					}
					break
				}
			}
		}
	})

	doc.Find("img").Each(func(i int, s *goquery.Selection) {
		imgURL := s.AttrOr("data-src", "")
		if imgURL == "" {
			imgURL = s.AttrOr("src", "")
		}

		if imgURL != "" {
			// Download image
			localFileName, err := c.downloadImage(imgURL, imagesDirPath)
			if err == nil {
				// Replace src with local relative path
				relativePath := filepath.Join(imagesDirName, localFileName)
				s.SetAttr("src", relativePath)
				// Remove data-src to ensure markdown converter uses src
				s.RemoveAttr("data-src")
			} else {
				fmt.Printf("Failed to download image %s: %v\n", imgURL, err)
			}
		}
	})

	newHTML, err := doc.Html()
	if err != nil {
		return err
	}

	// Workaround for <br> handling: Replace <br> with a placeholder to ensure it's preserved as a hard break
	// html-to-markdown/v2 might handle <br> differently depending on context or configuration.
	// We want explicit hard breaks (two spaces + newline) for every <br> tag.
	brPlaceholder := "WECHATBRHOLDER"
	// Replace the newline placeholder with the break placeholder
	newHTML = strings.ReplaceAll(newHTML, "WECHATNEWLINEHOLDER", brPlaceholder)

	// goquery normalizes to <br/> but we handle all cases just to be safe
	newHTML = strings.ReplaceAll(newHTML, "<br/>", brPlaceholder)
	newHTML = strings.ReplaceAll(newHTML, "<br>", brPlaceholder)
	newHTML = strings.ReplaceAll(newHTML, "<br />", brPlaceholder)

	markdown, err := md_convert.ConvertString(newHTML)
	if err != nil {
		return err
	}

	// Restore line breaks
	markdown = strings.ReplaceAll(markdown, brPlaceholder, "  \n")

	// Process additional images from article.Images
	if len(article.Images) > 0 {
		markdown += "\n\n"
		for _, imgURL := range article.Images {
			localFileName, err := c.downloadImage(imgURL, imagesDirPath)
			if err != nil {
				fmt.Printf("Failed to download attached image %s: %v\n", imgURL, err)
				continue
			}
			relative_path := filepath.Join(imagesDirName, localFileName)
			markdown += fmt.Sprintf("\n![image](%s)\n", relative_path)
		}
	}

	if err := os.MkdirAll(dir_path, 0755); err != nil {
		return err
	}

	if err := os.WriteFile(filePath, []byte(markdown), 0644); err != nil {
		return err
	}

	return nil
}

func (c *OfficialAccountDownload) BuildHTMLFromArticle(article *WechatOfficialArticle, need_compress_img bool) (string, error) {
	isImageArticle := article.Type == 2 && len(article.Images) > 0
	bodyMaxWidth := "677px"
	if isImageArticle {
		bodyMaxWidth = "1024px"
	}

	var htmlContent strings.Builder
	htmlContent.WriteString(`<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>`)
	htmlContent.WriteString(escapeHTML(article.Title))
	htmlContent.WriteString(`</title>
    <style>
        html { height: 100%; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            line-height: 1.6;
            max-width: ` + bodyMaxWidth + `;
            margin: 0 auto;
            padding: 20px;
            color: #333;`)
	if isImageArticle {
		htmlContent.WriteString(`
            height: 100%;
            overflow: hidden;
            box-sizing: border-box;`)
	}
	htmlContent.WriteString(`
        }
        h1 { font-size: 1.8em; margin-bottom: 0.5em; }
        .author { color: #666; margin-bottom: 20px; }
        .author img { width: 24px; height: 24px; border-radius: 50%; vertical-align: middle; margin-right: 8px; }
        img { max-width: 100%; height: auto; }
	.rich_media_title {
		font-size: 22px;
		line-height: 1.4;
		margin-bottom: 14px;
		font-weight: 500;
	}
	.not_in_mm .rich_media_meta_list {
		position: relative;
		z-index: 1;
	}
	.rich_media_meta_list {
		margin-bottom: 22px;
		line-height: 20px;
		font-size: 0;
		word-wrap: break-word;
		-webkit-hyphens: auto;
		-ms-hyphens: auto;
		hyphens: auto;
	}
	.rich_media_meta {
		display: inline-block;
		vertical-align: middle;
		margin: 0 10px 10px 0;
		font-size: 15px;
		-webkit-tap-highlight-color: rgba(0, 0, 0, 0);
	}
	.rich_media_meta_text.article_modify_tag, .rich_media_meta_nickname {
		position: relative;
	}
	.rich_media_meta_list em {
		font-style: normal;
	}
	.audio_card {
		display: flex;
		align-items: center;
		background-color: #f7f7f7;
		border-radius: 6px;
		padding: 12px;
		margin: 20px 0;
		border: 1px solid #ebebeb;
	}
	.audio_card_cover {
		width: 64px;
		height: 64px;
		border-radius: 4px;
		overflow: hidden;
		flex-shrink: 0;
		margin-right: 12px;
		position: relative;
	}
	.audio_card_cover img {
		width: 100%;
		height: 100%;
		object-fit: cover;
		display: block;
	}
	.audio_card_content {
		flex-grow: 1;
		overflow: hidden;
		margin-right: 12px;
	}
	.audio_card_title {
		font-size: 16px;
		font-weight: 500;
		color: #333;
		margin-bottom: 4px;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
	}
	.audio_card_meta {
		font-size: 13px;
		color: #999;
	}
	.audio_card audio {
		height: 32px;
	}
	.additional-images {
		margin-top: 0;
		padding-top: 0;
		border-top: none;
	}
	.additional-images img {
		display: block;
		width: 100%;
		height: auto;
		margin-bottom: 20px;
		border-radius: 6px;
		box-shadow: 0 2px 6px rgba(0,0,0,0.05);
	}
    /* Split layout styles */
    .split-container {
        display: flex;
        gap: 40px;
        align-items: flex-start;
        justify-content: center;
        height: 100%;
    }
    .split-left {
        width: 600px;
        flex: 0 0 600px;
        height: 100%;
        overflow-y: auto;
        scrollbar-width: thin;
    }
    .split-right {
        width: 344px;
        flex: 0 0 344px;
        height: 100%;
        overflow-y: auto;
        scrollbar-width: thin;
    }
    @media (max-width: 1000px) {
        html, body {
            height: auto !important;
            overflow: visible !important;
        }
        .split-container {
            display: block;
            height: auto;
        }
        .split-left, .split-right {
            width: 100%;
            flex: none;
            height: auto;
            overflow-y: visible;
        }
        .split-left {
            margin-bottom: 20px;
        }
    }
    </style>
</head>
<body>`)

	if isImageArticle {
		htmlContent.WriteString(`<div class="split-container"><div class="split-left"><div class="additional-images">`)
		for _, imgURL := range article.Images {
			imgData, mimeType, err := c.imageBytes(imgURL)
			if err == nil {
				if need_compress_img {
					// Compress image to reduce size
					compressedData, compressedMime, errCompress := compressImage(imgData)
					if errCompress == nil {
						fmt.Printf("Compressed image %s: %d -> %d bytes (%.2f%%)\n",
							imgURL, len(imgData), len(compressedData), float64(len(compressedData))/float64(len(imgData))*100)
						imgData = compressedData
						mimeType = compressedMime
					} else {
						fmt.Printf("Failed to compress image %s: %v\n", imgURL, errCompress)
					}
				}
				base64Str := base64.StdEncoding.EncodeToString(imgData)
				imgSrc := fmt.Sprintf("data:%s;base64,%s", mimeType, base64Str)
				htmlContent.WriteString(fmt.Sprintf("        <img src=\"%s\" alt=\"\">\n", imgSrc))
			} else {
				fmt.Printf("Failed to download image for base64 %s: %v\n", imgURL, err)
			}
		}
		htmlContent.WriteString(`</div></div><div class="split-right">`)
	}

	htmlContent.WriteString(`<h1 class="rich_media_title"><span>` + article.Title + "</span></h1>")
	creator_html := ""
	if article.Creator != "" {
		creator_html = `<span class="rich_media_meta rich_media_meta_text">` + article.Creator + `</span>`
	}
	htmlContent.WriteString(`<div class="rich_media_meta_list">` + creator_html + `<span class="rich_media_meta rich_media_meta_nickname">` + article.AuthorNickname + `</span><span><em class="rich_media_meta rich_media_meta_text">` + article.PublishTimeStr + "</em></span></div>")
	htmlContent.WriteString(`<div class="rich_media_content js_underline_content autoTypeSetting24psection fix_apple_default_style">`)
	// Process HTML content to handle newlines
	doc, err := goquery.NewDocumentFromReader(strings.NewReader(article.Content))
	if err != nil {
		htmlContent.WriteString(article.Content)
	} else {
		newlinePlaceholder := "WECHATNEWLINEHOLDER"
		var replaceNewlines func(*html.Node)
		replaceNewlines = func(n *html.Node) {
			if n.Type == html.TextNode {
				if strings.Contains(n.Data, "\n") {
					n.Data = strings.ReplaceAll(n.Data, "\n", newlinePlaceholder)
				}
				return
			}
			for c := n.FirstChild; c != nil; c = c.NextSibling {
				if c.Type == html.ElementNode {
					tag := strings.ToLower(c.Data)
					// Skip pre-formatted blocks
					if tag == "pre" || tag == "code" || tag == "script" || tag == "style" {
						continue
					}
				}
				replaceNewlines(c)
			}
		}

		for _, n := range doc.Nodes {
			replaceNewlines(n)
		}

		doc.Find("mp-common-mpaudio").Each(func(i int, s *goquery.Selection) {
			voiceEncodeFileId := s.AttrOr("voice_encode_fileid", "")
			if voiceEncodeFileId != "" {
				audioURL := "https://res.wx.qq.com/voice/getvoice?mediaid=" + voiceEncodeFileId
				name := s.AttrOr("name", "音频")
				poster := s.AttrOr("poster", "")
				if poster == "" {
					poster = s.AttrOr("cover", "")
				}

				html := fmt.Sprintf(`
				<div class="audio_card">
					<div class="audio_card_cover">
						<img src="%s" alt="cover">
					</div>
					<div class="audio_card_content">
						<div class="audio_card_title">%s</div>
						<audio src="%s" controls></audio>
					</div>
				</div>`, escapeHTML(poster), escapeHTML(name), audioURL)

				s.ReplaceWithHtml(html)
			}
		})

		doc.Find("iframe.video_iframe").Each(func(i int, s *goquery.Selection) {
			vid := s.AttrOr("data-vid", "")
			if vid == "" {
				vid = s.AttrOr("vid", "")
			}
			if vid == "" {
				vid = s.AttrOr("data-mpvid", "")
			}
			if vid != "" {
				for _, video := range article.Videos {
					if video.VideoID == vid {
						if len(video.MpVideoTransInfo) > 0 {
							videoURL := video.MpVideoTransInfo[0].Url
							cover := s.AttrOr("data-cover", "")
							posterAttr := ""
							if cover != "" {
								if decodedCover, err := url.QueryUnescape(cover); err == nil {
									cover = decodedCover
								}
								posterAttr = fmt.Sprintf(` poster="%s"`, escapeHTML(cover))
							}
							videoHTML := fmt.Sprintf(`<video src="%s"%s controls="controls" style="width: 100%%; height: auto;"></video>`, videoURL, posterAttr)
							s.ReplaceWithHtml(videoHTML)
						}
						break
					}
				}
			}
		})

		// Process images with data-src for base64 encoding
		doc.Find("img").Each(func(i int, s *goquery.Selection) {
			imgURL := s.AttrOr("data-src", "")
			if imgURL != "" {
				imgData, mimeType, err := c.imageBytes(imgURL)
				if err == nil {
					if need_compress_img {
						// Compress image to reduce size
						compressedData, compressedMime, errCompress := compressImage(imgData)
						if errCompress == nil {
							fmt.Printf("Compressed image %s: %d -> %d bytes (%.2f%%)\n",
								imgURL, len(imgData), len(compressedData), float64(len(compressedData))/float64(len(imgData))*100)
							imgData = compressedData
							mimeType = compressedMime
						} else {
							fmt.Printf("Failed to compress image %s: %v\n", imgURL, errCompress)
						}
					}
					base64Str := base64.StdEncoding.EncodeToString(imgData)
					imgSrc := fmt.Sprintf("data:%s;base64,%s", mimeType, base64Str)
					s.SetAttr("src", imgSrc)
					s.RemoveAttr("data-src")
				} else {
					fmt.Printf("Failed to download image for base64 %s: %v\n", imgURL, err)
				}
			}
		})

		// Get the content inside <body>
		newHTML, err := doc.Find("body").Html()
		if err != nil {
			htmlContent.WriteString(article.Content)
		} else {
			newHTML = strings.ReplaceAll(newHTML, newlinePlaceholder, "<br>")
			htmlContent.WriteString(newHTML)
		}
	}

	if isImageArticle {
		htmlContent.WriteString("    </div></div>")
	}

	htmlContent.WriteString(`</body>
</html>`)

	return htmlContent.String(), nil
}

func (c *OfficialAccountDownload) downloadImage(imgURL string, save_dir string) (string, error) {
	// Generate filename based on hash of URL
	hash := md5.Sum([]byte(imgURL))
	hashStr := hex.EncodeToString(hash[:])

	// Try to guess extension
	ext := ".jpg" // Default
	if strings.Contains(imgURL, "wx_fmt=png") {
		ext = ".png"
	} else if strings.Contains(imgURL, "wx_fmt=gif") {
		ext = ".gif"
	} else if strings.Contains(imgURL, "wx_fmt=jpeg") {
		ext = ".jpg"
	} else if strings.Contains(imgURL, "wx_fmt=webp") {
		ext = ".webp"
	} else {
		// Try to parse from URL path if query param not present
		u, err := url.Parse(imgURL)
		if err == nil {
			pathExt := filepath.Ext(u.Path)
			if pathExt != "" {
				ext = pathExt
			}
		}
	}

	filename := hashStr + ext
	filePath := filepath.Join(save_dir, filename)

	// Check if file already exists
	if data, err := os.ReadFile(filePath); err == nil {
		// Repeated logos and decorations are shared by many articles. Reuse the
		// existing local file for the embedded HTML as well.
		c.imageMu.Lock()
		if c.imageCache == nil {
			c.imageCache = make(map[string]cachedImage)
		}
		c.imageCache[imgURL] = cachedImage{data: data, mimeType: http.DetectContentType(data)}
		c.imageMu.Unlock()
		return filename, nil
	}

	data, _, err := c.imageBytes(imgURL)
	if err != nil {
		return "", err
	}
	if err := os.WriteFile(filePath, data, 0644); err != nil {
		return "", err
	}

	return filename, nil
}

func (c *OfficialAccountDownload) FetchArticle(url string) (*WechatOfficialArticle, error) {
	content, err := c.Scrape(url)
	if err != nil {
		return nil, err
	}
	content_str := string(content)
	// Extract createTime
	var publish_time_str string
	re := regexp.MustCompile(`var\s+createTime\s*=\s*'([^']+)'`)
	matches := re.FindStringSubmatch(content_str)
	if len(matches) > 1 {
		createTime := matches[1]
		t, err := time.Parse("2006-01-02 15:04", createTime)
		if err == nil {
			publish_time_str = t.Format("2006年01月02日 15:04")
		} else {
			publish_time_str = createTime
		}
	}
	data, err := parse_cgi_datanew(content_str)
	if err != nil {
		return nil, err
	}
	article := &WechatOfficialArticle{
		Type:           data.PageType,
		Title:          data.Title,
		Content:        data.ContentNoEncode,
		PublishTimeStr: publish_time_str,
		ContentLength:  len(data.ContentNoEncode),
		Creator:        data.Author,
		AuthorNickname: data.NickName,
		AuthorAvatar:   data.RoundHeadImg,
		AuthorID:       data.UserName,
		Images:         make([]string, 0),
		Videos:         data.VideoPageInfos,
	}
	// isImageArticle := data.PageType == 2
	if len(data.PicturePageInfoList) > 1 {
		for _, img := range data.PicturePageInfoList {
			if img.CdnUrl != "" {
				article.Images = append(article.Images, img.CdnUrl)
			}
		}
	}
	c.article = article
	return article, nil
}

func (c *OfficialAccountDownload) Scrape(rawURL string) ([]byte, error) {
	interval := c.ArticleRequestInterval
	maxAttempts := 1
	if interval > 0 && interval < safeArticleRequestInterval {
		maxAttempts = 3
	}
	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		requestInterval := interval
		if attempt > 0 {
			// A verification response is often a short-lived rate limit. Slow the
			// retry down before asking the user to reconnect in WeChat.
			time.Sleep(time.Duration(attempt*3) * time.Second)
			requestInterval = safeArticleRequestInterval
		}
		body, err := c.scrapeOnce(rawURL, requestInterval)
		if err == nil {
			return body, nil
		}
		lastErr = err
		if !isWeChatAccessVerificationError(err) {
			break
		}
	}
	return nil, lastErr
}

func (c *OfficialAccountDownload) scrapeOnce(rawURL string, interval time.Duration) ([]byte, error) {
	if rawURL == "" {
		return nil, fmt.Errorf("url is empty")
	}
	waitForArticleRequestSlot(interval)
	targetURL := rawURL
	var auth ArticleAuthCredential
	if ArticleAuthProvider != nil {
		if parsed, parseErr := url.Parse(rawURL); parseErr == nil {
			biz := parsed.Query().Get("__biz")
			if biz != "" {
				auth = ArticleAuthProvider(biz)
				query := parsed.Query()
				if auth.Uin != "" && query.Get("uin") == "" {
					query.Set("uin", auth.Uin)
				}
				if auth.Key != "" && query.Get("key") == "" {
					query.Set("key", auth.Key)
				}
				if auth.PassTicket != "" && query.Get("pass_ticket") == "" {
					query.Set("pass_ticket", auth.PassTicket)
				}
				if auth.Uin != "" || auth.Key != "" || auth.PassTicket != "" {
					if query.Get("devicetype") == "" {
						query.Set("devicetype", "UnifiedPCMac")
					}
					if query.Get("version") == "" {
						query.Set("version", "f2640619")
					}
					if query.Get("lang") == "" {
						query.Set("lang", "zh_CN")
					}
					if query.Get("ascene") == "" {
						query.Set("ascene", "1")
					}
					if query.Get("acctmode") == "" {
						query.Set("acctmode", "0")
					}
				}
				parsed.RawQuery = query.Encode()
				targetURL = parsed.String()
			}
		}
	}
	client := &http.Client{Timeout: 45 * time.Second}
	req, err := http.NewRequest("GET", targetURL, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7")
	req.Header.Set("accept-language", "zh-CN,zh;q=0.9,en;q=0.8")
	req.Header.Set("cache-control", "no-cache")
	req.Header.Set("pragma", "no-cache")
	req.Header.Set("priority", "u=0, i")
	req.Header.Set("sec-ch-ua", `"Not(A:Brand";v="8", "Chromium";v="144", "Google Chrome";v="144"`)
	req.Header.Set("sec-ch-ua-mobile", "?0")
	req.Header.Set("sec-ch-ua-platform", `"macOS"`)
	req.Header.Set("sec-fetch-dest", "document")
	req.Header.Set("sec-fetch-mode", "navigate")
	req.Header.Set("sec-fetch-site", "none")
	req.Header.Set("sec-fetch-user", "?1")
	req.Header.Set("upgrade-insecure-requests", "1")
	req.Header.Set("user-agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36")
	if auth.Cookie != "" {
		req.Header.Set("cookie", auth.Cookie)

	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.Request != nil && strings.Contains(resp.Request.URL.Path, "captcha") {
		return nil, fmt.Errorf("微信要求完成访问验证，请在微信中打开文章后重试")
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("微信返回 HTTP %d，请稍后重试", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if isWeChatVerificationPage(resp, body) {
		return nil, fmt.Errorf("微信公众号凭证已失效或触发访问验证，请在微信重新打开该公众号任意一篇文章后重试")
	}
	return body, err
}

func isWeChatAccessVerificationError(err error) bool {
	if err == nil {
		return false
	}
	message := err.Error()
	return strings.Contains(message, "访问验证") || strings.Contains(message, "凭证已失效")
}

func isWeChatVerificationPage(resp *http.Response, body []byte) bool {
	if resp != nil && resp.Request != nil && strings.Contains(resp.Request.URL.Path, "captcha") {
		return true
	}
	text := string(body)
	return strings.Contains(text, "poc_token") &&
		(strings.Contains(text, "TCaptcha") || strings.Contains(text, "secitptpage/template/verify"))
}

// ExtractArticleID extracts a unique article identifier from a WeChat official account URL.
// For short URLs like https://mp.weixin.qq.com/s/2kaR8z-xO_IAO9TPSUecsQ, returns the path suffix.
// For full URLs, returns mid+idx as the unique key.
// The rawURL may have an "officialaccount://" prefix.
func ExtractArticleID(rawURL string) string {
	u := rawURL
	lower := strings.ToLower(u)
	if strings.HasPrefix(lower, "officialaccount://") {
		u = u[len("officialaccount://"):]
		if !strings.HasPrefix(u, "http") {
			u = "https://" + u
		}
	}

	parsed, err := url.Parse(u)
	if err != nil {
		return ""
	}

	if !strings.Contains(parsed.Host, "mp.weixin.qq.com") {
		return ""
	}

	// Short URL: /s/2kaR8z-xO_IAO9TPSUecsQ
	path := strings.TrimRight(parsed.Path, "/")
	if strings.HasPrefix(path, "/s/") {
		shortID := strings.TrimPrefix(path, "/s/")
		if shortID != "" && !strings.Contains(shortID, "/") {
			return shortID
		}
	}

	// Full URL: extract mid+idx
	q := parsed.Query()
	mid := q.Get("mid")
	idx := q.Get("idx")
	if mid != "" {
		if idx == "" {
			idx = "1"
		}
		return mid + "_" + idx
	}

	return ""
}
