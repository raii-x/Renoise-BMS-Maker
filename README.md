# Renoise-BMS-Maker
BMS creation support tool for Renoise

## 機能
* BMS 制作時の音切り工程を行う。すなわち、それぞれのノートを単音の音声ファイルで書き出し、それらを BMS フォーマットで元のシーケンスを再現する。
* ソングファイルのトラックのうちの一つ以上を選択し、それらのトラック内にあるノートに対して音切りを行う。
* WAV 定義とシーケンスデータを含む BMS ファイルを出力する。
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
* Pattern の最大ライン数である 512 ライン以上のノートのレンダリング

## 必要なもの
* [Renoise 3.1.1](http://www.renoise.com/ "Home | Renoise")

## インストール方法
1. [Releases](https://github.com/raii-x/Renoise-BMS-Maker/releases "Releases · raii-x/Renoise-BMS-Maker") のページから、最新のバージョンの xrnx ファイルをダウンロードする。

2. ダウンロードした xrnx ファイルを Renoise で開く。

## 使い方
1. Tools メニューから Make BMS... を選択する。  
![Tools](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/tools.png)

2. BMS Maker ウィンドウで各種設定をする。  
![BMS Maker window](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/bms_maker2.png)

    * Track Options: 音切りするトラックごとの設定
        * 上部のボタン
            * Init:  
            各トラックの設定を初期化する。

            * Auto BGM Lane:  
            各トラックの BGM Lane をトラックの有効・無効、Chord 設定、Note コラム数から自動で設定する。

            * Refresh:  
            トラックがリネーム、追加、移動、削除などで変更された場合には、このボタンを押すことで変更を反映できる。

        * トラックリスト
            * 左のチェックボックス:  
            オンにしたトラックは有効となり、音切りの対象とする。見出し部のチェックボックスは、オンにすると全てのトラックがオンになり、オフにすると全てのトラックがオフになる。

            * Track:  
            設定の対象のトラック名が表示される。

            * 1-Shot:  
            オンの場合、長さの異なるノートでも同じノートとして扱う。ドラムなどではオンにするとよい。

            * Release:  
            1-Shot がオフの場合、ノートオフの後にレンダリングするライン数を設定。オンの場合、レンダリングするノート自体のライン数を設定。

            * Chord:  
            オンの場合、同時に発音する複数のノートをまとめて一つのノートとして扱う。コード系の楽器を一つのノートで鳴らしたいときにオンにするとよい。

            * BGM Lane:  
            BMS ファイルを書き出す際に、そのトラックのノートを置く BGM レーン番号を設定。

        * Prev, Next: トラック数が多い場合にページを切り替える。

    * Range: 音切り対象にする範囲の設定
        * Entire Song:  
        ソング全体

        * Selection in Sequence:  
        Pattern Sequencer で選択している範囲
        
        * Selection in Pattern:  
        Pattern Editor で選択している範囲。レンダリング時には選択範囲のトラックではなく、Track Options で指定したトラックが使われることに注意。

        * Custom:  
        Sequence 番号と Line 番号を直接指定

    * File Options: wav ファイルを出力するディレクトリを指定。Browse ボタンから選択することもできる。

    * Render Options: レンダリング時の設定。Renoise の Render to Disk の設定と同じ。

3. BMS Maker ウィンドウの Make ボタンを押し、音切りされた wav ファイルを出力し、BMS 出力に移る。または、Export only ボタンを押し、wav ファイルの出力を行わず、BMS の出力に移る。  
![Length exceed error](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/length_exceed_error.png)  
ここで、このエラーが表示される場合は、レンダリングするノートが長すぎるため wav ファイルを出力することができない。それらノートの開始位置のトラック、シーケンス番号、ライン番号が表示されている。ノートオフを入れるか、1-Shot にチェックを入れることで修正できる。

4. BMS Export ウィンドウで、BMS ファイルを出力する。  
![BMS Export window](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/bmse_export.png)

    * File Name:  
    出力する BMS ファイルの名前を指定。

    * Start Number:  
    BMS の WAV 定義の開始番号を指定。

    * Export:  
    BMS の出力を行う。

## 音切りの動作について
Track Options で指定された設定に基づいて各トラックを解析し、レンダリングするノートのデータを調べる。レンダリングの際は、ソングの最も上に新しいパターンを作り、ノートのデータを置いてレンダリングすることをノートの数だけ繰り返す。

![Note cutting example](https://raw.githubusercontent.com/raii-x/Renoise-BMS-Maker/images/note_cutting_example.png)

例として、図の (1) のようなシーケンスに対して処理すること考える。

1-Shot がオフ、Release が 2 の場合、図の (2) の 3 つのノートがレンダリングされる。1-Shot がオフの場合、ノートがあるラインから、次のノートの 1 つ上のラインか、次のノートオフの 1 つ上のラインか、Volume コラムか Panning コラムに Cx コマンドがあるラインまでが 1 つのノートとしてみなされる。レンダリングの際は、1 ノートの範囲の Note コラムと FX コラムのデータを使い、その後ろにノートオフを置き、ノートとその後の Release ライン数を書き出す。その際、書き出すライン数分のオートメーションのデータも使われる。ここで、ノートオフとその後のラインのコマンドは使われない。

1-Shot がオン、Release が 4 の場合、図の (3) の 3 つのノートがレンダリングされる。1-Shot がオンの場合、ノートがあるラインのみが 1 つのノートとしてみなされ、その後のコマンドは使われない。レンダリングの際には、Release ライン数が書き出され、そのライン数分のオートメーションも使われる。

レンダリングする際に使われるノートのデータが全く同じ場合は、それらを同じノートとして扱い、wav ファイルと定義番号を共有する。ここで多重定義は行われないので、必要なら手動で行うか、[Mid2BMS](http://mid2bms.web.fc2.com/ "Mid2BMS BMS Improved Development Environment") の自動重複定義などを利用すると良い。
