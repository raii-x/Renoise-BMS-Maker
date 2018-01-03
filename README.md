# Renoise-BMS-Maker
BMS creation support tool for Renoise

## 機能
* BMS 制作時の音切り工程を行う。すなわち、それぞれのノートを単音の音声ファイルで書き出し、それらを BMS フォーマットで元のシーケンスを再現する。
* 指定された一つのトラック内にあるノートに対して音切りを行う。
* BMS エディタでクリップボード貼り付け可能なシーケンスデータを出力する。
* オートメーションを含むトラックも再現することができる。
* 同じノートに対して同じ wav ファイルを使用することで、WAV 定義数と全体のファイルサイズを削減する。

## できないこと
* 補間方式が Linear 以外のオートメーションの再現
* オートメーションではなくコマンドを使ったデバイスパラメータの変化の再現
* LFO を持つデバイスの正しい位相の再現
* グループトラック、センドトラック、マスタートラックのオートメーションの再現
* Delay コラム、Delay コマンドを使ったノートの正しい位置での音切り
* Glide To Note コマンド、Instrument のグライド機能のピッチ変化の再現
* Maybe コマンド、ランダムLFO、Plugin Instrument のランダムなオシレータ開始位相などのランダム性の再現
* Arpeggio コマンド、Retrigger コマンドのエフェクトによる発音位置での音切り
* Phrase 内のノートの音切り
* サイドチェインなどの他のトラックの信号を使ったデバイスパラメータ変化の再現
* Pattern の最大ライン数である512ライン以上のノートのレンダリング

## 必要なもの
* [Renoise 3.1](http://www.renoise.com/ "Home | Renoise")
* [BMSE](http://ucn.tokonats.net/ "UCN-Soft")、[iBMSC](https://hitkey.nekokan.dyndns.info/ibmsc_ja/ "iBMSC - Home") などの BMSE ClipBoard Object Data Format をサポートしている BMS エディタ (iBMSC は Version 3.0.5 Delta 現在、複数レーンの BMS シーケンスには対応していないため、BMSEを推奨する)

## インストール方法
1. [Releases](https://github.com/raii-x/Renoise-BMS-Maker/releases "Releases · raii-x/Renoise-BMS-Maker") のページから、最新のバージョンの xrnx ファイルをダウンロードする。

2. Renoise でダウンロードした xrnx ファイルを開く。

## 使い方
1. Tools メニューから Make BMS... を選択する。  
![Tools](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/tools.png)

2. BMS Maker ウィンドウで各種設定をする。  
![BMS Maker window](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/bms_maker.png)

    * Range: 音切り対象にする範囲の設定
        * Entire Song:  
        ソング全体

        * Selection in Sequence:  
        Pattern Sequencer で選択している範囲
        
        * Selection in Pattern:  
        Pattern Editor で選択している範囲。レンダリング時には選択範囲のトラックではなく、カーソルのあるトラックが使われることに注意。

        * Custom:  
        Sequence 番号と Line 番号を直接指定

    * Note Options: 音切りするノートの設定
        * Has duration:  
        オンの場合、長さの違うノートを別のノートとして扱う。ドラムなどではオフにするとよい。

        * Release Lines:  
        Has duration がオンの場合、ノートオフの後にレンダリングするライン数を設定。オフの場合、レンダリングするノート自体のライン数を設定。

        * Chord Mode:  
        オンの場合、同時に発音する複数のノートをまとめて一つのノートとして扱う。コード系の楽器を一つのノートで鳴らしたいときにオンにするとよい。

    * File Options: 音切りされた wav ファイルの設定
        * 1行目:  
        wav ファイルを出力するディレクトリを指定。Browse ボタンから選択することもできる。

        * 2行目:  
        wav ファイルの名前を指定。ここで指定した文字列の後に `_***.wav` がつけれられたものがファイル名となる。`***` は3桁の数字である。

        * Start number:  
        wav ファイルの名前の後につけられる数字の開始番号を指定。

    * Render Options: レンダリング時の設定。Renoise の Render to Disk の設定と同じ。

3. 出力するトラックにカーソルを合わせる。

4. BMS Maker ウィンドウの Make ボタンを押し、音切りされた wav ファイルを出力し、BMS シーケンスの出力に移る。または、Export only ボタンを押し、wav ファイルの出力を行わず、BMS シーケンスの出力に移る。

5. BMSE Export ウィンドウで、BMS シーケンスをテキストファイルで出力する。  
![BMSE Export window](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/bmse_export.png)

    * File Name:  
    出力する BMS シーケンスのテキストファイルの名前を指定。

    * Start Number:  
    BMS の WAV 定義の開始番号を指定。

    * Export:  
    BMS シーケンスの出力を行う。

6. 出力された wav ファイルをすべて選択し、BMS エディタの WAV 定義欄にドラッグ＆ドロップする。  
![WAV drag & drop](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/wav_drag.png)

7. 出力されたテキストファイルの全文をコピーし、BMS エディタで貼り付けを行う。
