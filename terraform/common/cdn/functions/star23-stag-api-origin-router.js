import cf from 'cloudfront';

function handler(event) {
  var request = event.request;
  var host = request.headers.host && request.headers.host.value.toLowerCase();
  var isApi = request.uri === '/api' || request.uri.indexOf('/api/') === 0;
  var isWebSocket = request.uri === '/ws' || request.uri.indexOf('/ws/') === 0;

  // Keep staging's existing API routing; staging WebSocket still uses the ECS origin.
  if (host === 'stag.star23sharp.com' && isApi) {
    cf.updateRequestOrigin({
      domainName: 'star23-staging-alb-15032452.ap-northeast-2.elb.amazonaws.com',
      hostHeader: 'stag.star23sharp.com',
      customOriginConfig: {
        port: 443,
        protocol: 'https',
        sslProtocols: ['TLSv1.2'],
      },
      sni: 'api.star23sharp.com',
      allowedCertificateNames: ['api.star23sharp.com'],
    });
  }

  if ((host === 'star23sharp.com' || host === 'v3.star23sharp.com') && (isApi || isWebSocket)) {
    cf.updateRequestOrigin({
      domainName: 'star23-v3-alb-1133942644.ap-northeast-2.elb.amazonaws.com',
      hostHeader: 'v3.star23sharp.com',
      customOriginConfig: {
        port: 443,
        protocol: 'https',
        sslProtocols: ['TLSv1.2'],
      },
      sni: 'api.star23sharp.com',
      allowedCertificateNames: ['api.star23sharp.com'],
    });
  }

  return request;
}
