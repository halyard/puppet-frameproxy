from mitmproxy import http
from mitmproxy import ctx

import os
import hashlib

class FrameProxy:
    path = "/opt/cache"

    def response(self, flow: http.HTTPFlow) -> None:
        path = os.path.join(self.path, self.url_to_file(flow.request.path))
        if not os.path.isfile(path):
            if not os.path.exists(os.path.dirname(path)):
                os.makedirs(os.path.dirname(path))
            with open(path, "w") as cache_file:
                file.write(flow.response.text)

    def request(self, flow: http.HTTPFlow) -> None:
        path = os.path.join(self.path, self.url_to_file(flow.request.path))
        if os.path.isfile(path):
            with open(path, 'r') as cache_file:
                cache_content = cache_file.read()
            flow.response = http.HTTPResponse.make(200, cache_content)

    def url_to_file(self, path: str) -> str:
        url = path.split('?')[0]
        filename = hashlib.sha512(url.encode('utf-8')).hexdigest()
        return filename

addons = [FrameProxy()]
