# google-lighthouse-api

Runs an API call to Google's lighthouse page speed insight then parses out some valuable data that pertains to website performance. Desktop only

First use the --api flag to set the api key. Or, if you need to change the key. 

Example API:
perl google-lighthouse-api/githublighthouse.pl --api $api_key

Your API key can be generated following the steps here:
https://developers.google.com/speed/docs/insights/v5/

After that has been set, the normal usage is to pass it a domain either naked or with the http/s. If naked is used, Https will be prefixed to it and run "https://$original_url"

Example Run:
perl google-lighthouse-api/githublighthouse.pl example.com

Example output:

:: Google Lighthouse PageSpeed Insights API ::

Metric                Value                      Explanation
TTFB                  0.041 seconds              https://developer.chrome.com/docs/lighthouse/performance/time-to-first-byte/
Full Load Time        0.9 s                      https://developer.chrome.com/docs/lighthouse/performance/interactive/
FCP                   0.9 s                      https://developer.chrome.com/docs/lighthouse/performance/first-contentful-paint/
LCP                   0.9 s                      https://developer.chrome.com/docs/lighthouse/performance/lighthouse-largest-contentful-paint/
Properly size images  Potential Savings 35.05 KB https://developer.chrome.com/docs/lighthouse/performance/uses-responsive-images/
Minify CSS            Potential Savings 0.00 KB  https://developer.chrome.com/docs/lighthouse/performance/unminified-css/
Minify JS             Potential Savings 0.00 KB  https://developer.chrome.com/docs/lighthouse/performance/unminified-javascript/
Unused JS             Potential Savings 0.00 KB  https://developer.chrome.com/docs/lighthouse/performance/unused-javascript/
Unused CSS            Potential Savings 61.65 KB https://developer.chrome.com/docs/lighthouse/performance/unused-css-rules/
Total Page Size       0.36 MB                    https://developer.chrome.com/docs/lighthouse/performance/total-byte-weight/
Total Requests        48                         Lists the network requests that were made during page load.

Page Details:
Resource Type        |   Count |       Size (MB) | Percentage of Bytes
-------------------- | ------- | --------------- | ------------------------
Document             |       1 |            0.01 |     3.32%
Font                 |       3 |            0.15 |    41.67%
Image                |       2 |            0.04 |    11.64%
Other                |       1 |            0.00 |     0.00%
JS                   |      26 |            0.07 |    18.93%
CSS                  |      14 |            0.09 |    24.44%
---------------------------------------------------------------------------
