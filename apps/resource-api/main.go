package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

var (
	bucketName string
	region     string
	s3Client   *s3.Client
	appVersion string
)

func init() {
	bucketName = getEnv("BUCKET_NAME", "crossplane-demo-bucket")
	region = getEnv("AWS_REGION", "us-east-1")
	appVersion = getEnv("APP_VERSION", "v1")
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func initS3Client() error {
	endpoint := os.Getenv("S3_ENDPOINT")
	var opts []func(*config.LoadOptions) error
	opts = append(opts, config.WithRegion(region))

	if endpoint != "" {
		customResolver := aws.EndpointResolverWithOptionsFunc(
			func(service, reg string, options ...interface{}) (aws.Endpoint, error) {
				return aws.Endpoint{
					URL:               endpoint,
					HostnameImmutable: true,
				}, nil
			})
		opts = append(opts, config.WithEndpointResolverWithOptions(customResolver))
	}

	cfg, err := config.LoadDefaultConfig(context.Background(), opts...)
	if err != nil {
		return fmt.Errorf("unable to load AWS config: %w", err)
	}
	s3Client = s3.NewFromConfig(cfg, func(o *s3.Options) {
		if endpoint != "" {
			o.UsePathStyle = true
		}
	})
	return nil
}

type healthResponse struct {
	Status  string `json:"status"`
	Version string `json:"version"`
	Bucket  string `json:"bucket"`
	Region  string `json:"region"`
}

type putRequest struct {
	Key     string `json:"key"`
	Content string `json:"content"`
}

type listResponse struct {
	Bucket  string   `json:"bucket"`
	Objects []string `json:"objects"`
	Count   int      `json:"count"`
}

type getResponse struct {
	Bucket  string `json:"bucket"`
	Key     string `json:"key"`
	Content string `json:"content"`
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	resp := healthResponse{
		Status:  "healthy",
		Version: appVersion,
		Bucket:  bucketName,
		Region:  region,
	}
	writeJSON(w, http.StatusOK, resp)
}

func listObjectsHandler(w http.ResponseWriter, r *http.Request) {
	if s3Client == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "S3 client not initialized — bucket may not be provisioned yet",
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	output, err := s3Client.ListObjectsV2(ctx, &s3.ListObjectsV2Input{
		Bucket: aws.String(bucketName),
	})
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": fmt.Sprintf("failed to list objects: %v", err),
		})
		return
	}

	keys := make([]string, 0, len(output.Contents))
	for _, obj := range output.Contents {
		keys = append(keys, *obj.Key)
	}

	writeJSON(w, http.StatusOK, listResponse{
		Bucket:  bucketName,
		Objects: keys,
		Count:   len(keys),
	})
}

func putObjectHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "POST only", http.StatusMethodNotAllowed)
		return
	}
	if s3Client == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "S3 client not initialized — bucket may not be provisioned yet",
		})
		return
	}

	var req putRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("invalid JSON: %v", err),
		})
		return
	}
	if req.Key == "" || req.Content == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "key and content are required",
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	_, err := s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(req.Key),
		Body:   strings.NewReader(req.Content),
	})
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": fmt.Sprintf("failed to put object: %v", err),
		})
		return
	}

	writeJSON(w, http.StatusCreated, map[string]string{
		"message": fmt.Sprintf("object '%s' created in bucket '%s'", req.Key, bucketName),
	})
}

func getObjectHandler(w http.ResponseWriter, r *http.Request) {
	if s3Client == nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"error": "S3 client not initialized — bucket may not be provisioned yet",
		})
		return
	}

	key := r.URL.Query().Get("key")
	if key == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "query parameter 'key' is required",
		})
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()

	output, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucketName),
		Key:    aws.String(key),
	})
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": fmt.Sprintf("failed to get object: %v", err),
		})
		return
	}
	defer output.Body.Close()

	body, err := io.ReadAll(output.Body)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": fmt.Sprintf("failed to read object body: %v", err),
		})
		return
	}

	writeJSON(w, http.StatusOK, getResponse{
		Bucket:  bucketName,
		Key:     key,
		Content: string(body),
	})
}

func writeJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func main() {
	if err := initS3Client(); err != nil {
		log.Printf("[WARN] S3 client init failed (bucket may not exist yet): %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/objects", listObjectsHandler)
	mux.HandleFunc("/api/object", getObjectHandler)
	mux.HandleFunc("/api/object/put", putObjectHandler)

	port := getEnv("PORT", "8080")
	log.Printf("[INFO] resource-api %s starting on :%s (bucket=%s, region=%s)", appVersion, port, bucketName, region)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatalf("[FATAL] server failed: %v", err)
	}
}
