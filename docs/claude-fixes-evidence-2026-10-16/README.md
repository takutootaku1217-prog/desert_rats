# 検証証跡

最終判定は core-v4 と endurance-v4-501/502/503 の results.json と隣接ログ。各最終実行はソース変更なし。
enduranceの成功は観測の整合性を指し、生存は各ログ末尾のresultで別記する。
baseline-501-stay.log / baseline-501-hunt.log は修正前。その他は中間試行で、失敗・中断を成功として扱わない。
core-final3 は51/52成功の中間結果。core-final/core-final2とendurance-final-*等は中断した試行を含む。rawのstatusがrunningでも最終判定ではない。
ログは生成時の末尾空白も含め原文保持。results.json内の絶対パスは実行時の保存先。再配布した同名ログは同じディレクトリにある。
巨大なGodotキャッシュ・user://一時画像・セーブfixtureは含めず、ログと結果JSONを保存した。
final-source-sha256.jsonは検証した17ファイルの内容。検証後に追加したのは記録・証跡とCLAUDE作業ログ。
