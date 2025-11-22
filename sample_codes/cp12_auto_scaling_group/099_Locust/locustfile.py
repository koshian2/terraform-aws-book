# 最小限のLocustの例
from locust import HttpUser, task, between, LoadTestShape

class AlbUser(HttpUser):
    # ----------------------------------------------------
    # 実行時に --host オプションでURLを指定してください。
    # ----------------------------------------------------

    # タスク間の待ち時間 (1〜3秒のランダム)
    wait_time = between(1, 3)

    @task
    def access_alb_root(self):
        """
        仮想ユーザーが行うタスク (ALBのルートパス "/" にGETリクエスト)

        self.client.get()は自動的にレスポンスタイムを計測し、
        失敗したリクエスト(5xxエラーなど)を記録します。
        """
        # self.host は --host で指定された値が自動的に使われます
        self.client.get("/")

class StagedLoadShape(LoadTestShape):
    """
    時間経過でユーザー数を変更する負荷シェイプ（ステージ定義）
    
    ・最初の1分 (0-60秒): 5 ユーザー
    ・次の1分 (60-120秒): 10 ユーザー
    ・最後の1分 (120-180秒): 20 ユーザー
    """
    
    def tick(self):
        run_time = self.get_run_time() # 実行からの経過秒数を取得

        if run_time < 60:
            # --- ステージ1 (1分目) ---
            return (5, 5) # (総ユーザー数 5, スポーンレート 5)
        
        elif run_time < 120:
            # --- ステージ2 (2分目) ---
            return (10, 5) # (総ユーザー数 10, スポーンレート 5)
        
        elif run_time < 180:
            # --- ステージ3 (3分目) ---
            return (20, 10) # (総ユーザー数 20, スポーンレート 10)
        
        else:
            # --- テスト終了 ---
            return None