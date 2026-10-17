import com.graphhopper.routing.ev.*;
import com.graphhopper.routing.util.EncodingManager;
import com.graphhopper.storage.*;
import com.graphhopper.util.*;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;

/** Read-only export from the checksum-pinned GraphHopper 11.1 base graph.
 * Output is JSON Lines in GeoJSON coordinate order (longitude, latitude).
 * IDs are meaningful only within the supplied immutable graph version.
 */
public final class ExportEdges {
  public static void main(String[] args) throws Exception {
    if (args.length != 3) throw new IllegalArgumentException("Expected graph directory, import date and output path");
    Path output = Path.of(args[2]);
    if (Files.exists(output)) throw new IllegalArgumentException("Output already exists");
    GHDirectory directory = new GHDirectory(args[0], DAType.MMAP_RO);
    StorableProperties properties = new StorableProperties(directory);
    BaseGraph graph = null;
    try {
      if (!properties.loadExisting() || !args[1].equals(properties.get("datareader.import.date")))
        throw new IllegalStateException("Graph import provenance mismatch");
      EncodingManager encoding = EncodingManager.fromProperties(properties);
      graph = new BaseGraph.Builder(encoding).setDir(directory).set3D(false).build();
      if (!graph.loadExisting()) throw new IllegalStateException("Graph cannot be loaded");
      var car = encoding.getBooleanEncodedValue("car_access");
      var foot = encoding.getBooleanEncodedValue("foot_access");
      var carSubnetwork = encoding.getBooleanEncodedValue("car_subnetwork");
      var footSubnetwork = encoding.getBooleanEncodedValue("foot_subnetwork");
      var roadAccess = encoding.getEnumEncodedValue("road_access", RoadAccess.class);
      var footAccess = encoding.getEnumEncodedValue("foot_road_access", FootRoadAccess.class);
      var hike = encoding.getIntEncodedValue("hike_rating");
      var carSpeed = encoding.getDecimalEncodedValue("car_average_speed");
      var footSpeed = encoding.getDecimalEncodedValue("foot_average_speed");
      int exported = 0, degenerate = 0;
      try (var writer = Files.newBufferedWriter(output, StandardCharsets.UTF_8, StandardOpenOption.CREATE_NEW)) {
        var edges = graph.getAllEdges();
        while (edges.next()) {
          boolean carAllowed = edges.get(roadAccess) == RoadAccess.YES && !edges.get(carSubnetwork);
          var footRoad = edges.get(footAccess);
          boolean footAllowed = (footRoad == FootRoadAccess.MISSING || footRoad == FootRoadAccess.YES || footRoad == FootRoadAccess.DESIGNATED)
            && edges.get(hike) < 2 && !edges.get(footSubnetwork);
          boolean carForward = carAllowed && edges.get(car) && edges.get(carSpeed) > 0;
          boolean carReverse = carAllowed && edges.getReverse(car) && edges.getReverse(carSpeed) > 0;
          boolean footForward = footAllowed && edges.get(foot) && edges.get(footSpeed) > 0;
          boolean footReverse = footAllowed && edges.getReverse(foot) && edges.getReverse(footSpeed) > 0;
          if (!carForward && !carReverse && !footForward && !footReverse) continue;
          PointList points = edges.fetchWayGeometry(FetchMode.ALL);
          if (points.size() < 2 || !Double.isFinite(edges.getDistance()) || edges.getDistance() <= 0) continue;
          boolean distinct = false;
          for (int i = 1; i < points.size(); i++)
            distinct |= points.getLat(i) != points.getLat(0) || points.getLon(i) != points.getLon(0);
          // GraphHopper can retain 1 mm connector edges whose quantized geometry
          // is a single point. They remain in the router, but are not a road on
          // which a spatial observation can be associated.
          if (!distinct) { degenerate++; continue; }
          var line = new StringBuilder("{\"edgeId\":").append(edges.getEdge())
            .append(",\"forwardKey\":").append(edges.getEdgeKey()).append(",\"reverseKey\":").append(edges.getReverseEdgeKey())
            .append(",\"carForward\":").append(carForward).append(",\"carReverse\":").append(carReverse)
            .append(",\"footForward\":").append(footForward).append(",\"footReverse\":").append(footReverse)
            .append(",\"lengthMetres\":").append(edges.getDistance()).append(",\"geometry\":{\"type\":\"LineString\",\"coordinates\":[");
          for (int i = 0; i < points.size(); i++) {
            if (!Double.isFinite(points.getLat(i)) || !Double.isFinite(points.getLon(i))) throw new IllegalStateException("Invalid graph coordinate");
            if (i > 0) line.append(',');
            line.append('[').append(points.getLon(i)).append(',').append(points.getLat(i)).append(']');
          }
          writer.write(line.append("]}}").toString());
          writer.newLine();
          exported++;
        }
      }
      System.out.println("Exported " + exported + " spatially usable traversable edges from " + graph.getNodes() + " nodes / " + graph.getEdges() + " base edges; skipped " + degenerate + " point-only connectors.");
    } finally {
      if (graph != null) graph.close();
      properties.close();
      directory.close();
    }
  }
}
