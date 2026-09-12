package main

import (
	"fmt"
	"os"

	"github.com/gin-gonic/gin"

	"mp_article_batch_downloader/cmd"
	"mp_article_batch_downloader/internal/config"
)

var AppVer = "260614"
var Mode = "debug"

func main() {
	if Mode == "release" {
		gin.SetMode(gin.ReleaseMode)
	}
	cfg := config.New(AppVer, Mode)
	if err := cmd.Execute(cfg); err != nil {
		fmt.Printf("运行失败 %v\n", err.Error())
		os.Exit(1)
	}
}
