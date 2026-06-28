# 最小限のLocustの例 / Minimal Locust example.
from locust import HttpUser, task, between, LoadTestShape

class AlbUser(HttpUser):
    # ----------------------------------------------------
    # 実行時に --host オプションでURLを指定してください。 / Specify the URL with the --host option at runtime.
    # ----------------------------------------------------

    # タスク間の待ち時間 (1〜3秒のランダム) / Wait time between tasks. Random 1 to 3 seconds.
    wait_time = between(1, 3)

    @task
    def access_alb_root(self):
        """
        仮想ユーザーが行うタスク (ALBのルートパス "/" にGETリクエスト) / Task run by a virtual user. Sends a GET request to the ALB root path "/".

        self.client.get()は自動的にレスポンスタイムを計測し、 / self.client.get() automatically measures response time,
        失敗したリクエスト(5xxエラーなど)を記録します。 / and records failed requests, such as 5xx errors.
        """
        # self.host は --host で指定された値が自動的に使われます / self.host automatically uses the value specified with --host
        self.client.get("/")

class StagedLoadShape(LoadTestShape):
    """
    時間経過でユーザー数を変更する負荷シェイプ（ステージ定義） / Load shape that changes the number of users over time. Stage definition.
    
    ・最初の1分 (0-60秒): 5 ユーザー / First minute, 0 to 60 seconds: 5 users.
    ・次の1分 (60-120秒): 10 ユーザー / Next minute, 60 to 120 seconds: 10 users.
    ・最後の1分 (120-180秒): 20 ユーザー / Last minute, 120 to 180 seconds: 20 users.
    """
    
    def tick(self):
        run_time = self.get_run_time() # 実行からの経過秒数を取得 / Get elapsed seconds since the run started

        if run_time < 60:
            # --- ステージ1 (1分目) --- / Stage 1: first minute
            return (5, 5) # (総ユーザー数 5, スポーンレート 5) / Total users 5, spawn rate 5.
        
        elif run_time < 120:
            # --- ステージ2 (2分目) --- / Stage 2: second minute.
            return (10, 5) # (総ユーザー数 10, スポーンレート 5) / Total users 10, spawn rate 5.
        
        elif run_time < 180:
            # --- ステージ3 (3分目) --- / Stage 3: third minute.
            return (20, 10) # (総ユーザー数 20, スポーンレート 10) / Total users 20, spawn rate 10.
        
        else:
            # --- テスト終了 --- / End the test.
            return None
