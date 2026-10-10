package demo;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.time.Duration;

public final class SmokeTest {
    static void require(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    public static void main(String[] args) throws Exception {
        require(Main.json("a\"b\nc").equals("\"a\\\"b\\nc\""), "JSON escaping");
        String value = System.getenv("DEMO_MESSAGE");
        require(value != null && !value.isBlank(), "Vault-derived environment must exist before build tests");
        var file = Files.createTempFile("config-test", ".properties");
        Files.writeString(file, "demo.property=local-test\n");
        exercise(file, false);
        exercise(file, true);
        Files.deleteIfExists(file);
        System.out.println("PASS: Java21 HTTP, JSON, env before build, redacted and demo modes, local config, methods");
    }
    static void exercise(java.nio.file.Path file, boolean expose) throws Exception {
        var process = new ProcessBuilder("java", "-cp", "build/classes", "demo.Main");
        process.environment().put("CONFIG_PATH", file.toString());
        process.environment().put("EXPOSE_DEMO_VALUE", Boolean.toString(expose));
        var child = process.start();
        try {
            var client = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
            HttpResponse<String> health = null;
            for (int i = 0; i < 40; i++) {
                try { health = client.send(HttpRequest.newBuilder(URI.create("http://localhost:8080/health/ready")).timeout(Duration.ofSeconds(2)).build(), HttpResponse.BodyHandlers.ofString()); break; }
                catch (java.io.IOException e) { Thread.sleep(100); }
            }
            require(health != null && health.statusCode() == 200, "readiness");
            var secret = client.send(HttpRequest.newBuilder(URI.create("http://localhost:8080/api/secret")).build(), HttpResponse.BodyHandlers.ofString());
            require(secret.statusCode() == 200 && secret.body().equals("{\"value\":" + Main.json(expose ? System.getenv("DEMO_MESSAGE") : "[REDACTED]") + "}"), "secret redaction default");
            var config = client.send(HttpRequest.newBuilder(URI.create("http://localhost:8080/api/config")).build(), HttpResponse.BodyHandlers.ofString());
            require(config.statusCode() == 200 && config.body().contains("local-test"), "local property endpoint");
            var method = client.send(HttpRequest.newBuilder(URI.create("http://localhost:8080/api/secret")).POST(HttpRequest.BodyPublishers.noBody()).build(), HttpResponse.BodyHandlers.ofString());
            require(method.statusCode() == 405, "reject unexpected methods");
        } finally { child.destroy(); child.waitFor(); }
    }
}
