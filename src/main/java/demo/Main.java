package demo;

import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;
import java.util.concurrent.Executors;

/** Demo values only: never expose a production credential through these endpoints. */
public final class Main {
    static String json(String value) {
        var out = new StringBuilder("\"");
        for (char c : value.toCharArray()) {
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                default -> { if (c < 32) out.append(String.format("\\u%04x", (int)c)); else out.append(c); }
            }
        }
        return out.append('"').toString();
    }
    public static void main(String[] args) throws Exception {
        String value = System.getenv("DEMO_MESSAGE");
        if (value == null || value.isBlank()) throw new IllegalStateException("DEMO_MESSAGE is required");
        var config = new Properties();
        try (var input = Files.newInputStream(Path.of(System.getenv().getOrDefault("CONFIG_PATH", "/app/config/application.properties")))) {
            config.load(input);
        }
        String property = config.getProperty("demo.property");
        if (property == null || property.isBlank()) throw new IllegalStateException("demo.property is required");
        String feature = System.getenv().getOrDefault("VSO_FEATURE_FLAG", "not-configured");
        boolean expose = "true".equals(System.getenv("EXPOSE_DEMO_VALUE"));
        var server = HttpServer.create(new InetSocketAddress(8080), 0);
        server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
        server.createContext("/", exchange -> {
            int status = 200;
            String response;
            if (!"GET".equals(exchange.getRequestMethod())) { status = 405; response = "{\"error\":\"method not allowed\"}"; }
            else {
                switch (exchange.getRequestURI().getPath()) {
                    case "/health/live", "/health/ready" -> response = "{\"status\":\"UP\"}";
                    case "/api/secret" -> response = "{\"value\":" + json(expose ? value : "[REDACTED]") + "}";
                    case "/api/config" -> response = "{\"property\":" + json(property) + ",\"feature\":" + json(feature) + "}";
                    default -> { status = 404; response = "{\"error\":\"not found\"}"; }
                }
            }
            byte[] body = response.getBytes(StandardCharsets.UTF_8);
            exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
            exchange.getResponseHeaders().set("Cache-Control", "no-store");
            exchange.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
            exchange.sendResponseHeaders(status, body.length);
            try (var output = exchange.getResponseBody()) { output.write(body); }
        });
        Runtime.getRuntime().addShutdownHook(new Thread(() -> server.stop(2)));
        server.start();
        System.out.println("Java 21 service listening on 8080; configuration loaded; values omitted.");
    }
}
