package org.booklore.service.reader;

import lombok.AllArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.booklore.util.FileService;
import org.springframework.stereotype.Service;

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

@Slf4j
@Service
@AllArgsConstructor
public class FfprobeService {
    public Path getFfprobeBinary() {
        try {
            return Paths.get("ffprobe").toAbsolutePath();
        } catch (Exception e) {
            log.warn("Failed to find ffprobe binary: {}", e.getMessage());
            return null;
        }
    }
}
