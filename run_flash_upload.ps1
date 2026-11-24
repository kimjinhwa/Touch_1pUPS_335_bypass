# 1pUPS bypass 전용 이미지 업로드 GUI.

$SketchDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $SketchDir
python tools\flash_upload\flash_upload.py
