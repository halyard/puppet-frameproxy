from mitmproxy import http
from mitmproxy import ctx

import os
import hashlib
import logging
from urllib.parse import urlparse

pattern = 'https://{0}/_cache_/{1}/{2}{3}?{4}'

def url_to_file(path: str) -> str:
    url = path.split('?')[0]
    filename = hashlib.sha512(url.encode('utf-8')).hexdigest()
    return filename

def is_s3(parts: list[str]) -> bool:
    if len(parts) == 5 and parts[1] == 's3' and parts[3] == 'amazonaws' and parts[4] == 'com':
        return True
    return False

class FrameProxy:
    cache_dir = "/opt/cache"

    def response(self, flow: http.HTTPFlow) -> None:
        if flow.response.status_code == 303:
            parsed = urlparse(flow.response.headers['location'])
            parts = parsed.netloc.split('.')
            logging.info('Matched 303 on response: {0}'.format(parsed.netloc))
            if is_s3(parts):
                logging.info('Confirmed 303 is S3: {0}'.format(parts[0]))
                cache_url = pattern.format(
                        flow.request.host,
                        parts[0],
                        parts[2],
                        parsed.path,
                        parsed.query)
                flow.response.headers['location'] = cache_url
                logging.info('Rewriting to cache: {0}'.format(cache_url))
                return

        if flow.response.status_code != 200:
            logging.info('Ignoring non-200 response: {0}'.format(flow.request.host))
            return

        parsed = urlparse(flow.request.url)
        parts = parsed.netloc.split('.')
        if not is_s3(parts):
            return
        logging.info('Matched S3 response: {0}'.format(parts[0]))
        path = os.path.join(self.cache_dir, url_to_file(flow.request.path))
        if not os.path.isfile(path):
            logging.info('Writing cache file: {0}'.format(path))
            if not os.path.exists(os.path.dirname(path)):
                os.makedirs(os.path.dirname(path))
            with open(path, "w") as cache_file:
                cache_file.write(flow.response.text)

    def request(self, flow: http.HTTPFlow) -> None:
        if not flow.request.path.startswith("/_cache_/"):
            return
        path = os.path.join(self.cache_dir, url_to_file(flow.request.path))
        logging.info('Received cache request: {0}'.format(path))
        if os.path.isfile(path):
            logging.info('Cache hit: {0}'.format(path))
            with open(path, 'r') as cache_file:
                cache_content = cache_file.read()
                flow.response = http.Response.make(200, cache_content)
                return
        logging.info('Cache miss: {0}'.format(path))
        parts = flow.request.path.split('/', 4)
        real_url = 'https://{0}.s3.{1}.amazonaws.com/{2}'.format(parts[2], parts[3], parts[4])
        flow.request.url = real_url
        logging.info('Rewriting to real URL: {0}'.format(real_url))
        flow.request.host = '{0}.s3.{1}.amazonaws.com'.format(parts[2], parts[3])
        flow.request.path = '/' + parts[4]
        flow.request.headers.pop('Authorization', None)

addons = [FrameProxy()]

